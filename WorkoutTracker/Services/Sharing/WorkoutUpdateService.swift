import Foundation
import SwiftData

/// Turns "this followed workout has a pending update" into one of three outcomes
/// `WorkoutUpdateReviewView` offers: merged in place (unlocked only), saved as an
/// independent copy (unlocked only), or versioned like a user's own locked-and-edited
/// workout (locked only).
///
/// Same shape as a fresh download (`FollowedUserDetailView.prepareDownload` →
/// `SharedWorkoutImporter`) because it *is* that path up to a point — download, resolve
/// the catalog — and only diverges once there's a `Workout` to compare against instead of
/// only ever a `Workout` to create. The one rule that matters throughout: nothing before
/// `applyInPlace`/`saveAsCopy`/`saveAsNewVersion` ever writes to the store. `preparePlan`
/// only downloads and plans (`CatalogImportPlanner.plan`, itself read-only); `computeDiff`
/// only reads. Commit — `CatalogMerge.apply`, which does write — happens exactly once,
/// inside whichever of the final actions the user actually picks, so backing out of the
/// review (or the catalog sub-review `SharedImportReviewView` might show first) never
/// leaves behind a catalog row nobody asked for.
@MainActor
enum WorkoutUpdateService {
    struct UpdatePlan {
        let workout: Workout
        let bundle: SharedWorkoutBundle
        var catalogPlan: SharedWorkoutPlan
    }

    /// Finds the publisher's current copy of `workout` and downloads it. `nil` means the
    /// publisher's record disappeared between the sweep noticing an update and this
    /// running — unpublished or deleted in between — which is not an error, just nothing
    /// left to show.
    static func preparePlan(for workout: Workout, context: ModelContext) async throws -> UpdatePlan? {
        guard let ownerRecordName = workout.sourceOwnerRecordName,
              let publisherWorkoutID = workout.clonedFromWorkoutId
        else { return nil }

        let summaries = try await SharingService.publishedWorkouts(ownerRecordName: ownerRecordName)
        guard let summary = summaries.first(where: { $0.workoutID == publisherWorkoutID }) else { return nil }

        let bundle = try await SharingService.download(summary)
        let catalogPlan = try SharedWorkoutImporter.plan([bundle], context: context)
        return UpdatePlan(workout: workout, bundle: bundle, catalogPlan: catalogPlan)
    }

    /// What changed, computed against the (possibly user-adjusted) catalog *plan* —
    /// never applied. Safe to call as many times as the catalog sub-review reruns it.
    static func computeDiff(_ plan: UpdatePlan, context: ModelContext) -> [WorkoutDifference] {
        WorkoutDifferenceCalculator.compute(
            local: plan.workout,
            payload: plan.bundle.payload,
            catalog: plan.catalogPlan.catalog,
            context: context
        )
    }

    /// The only place either final action calls into `CatalogMerge`/`ProgressionMerge` —
    /// see the enum's own doc comment for why that has to be exactly once, and only here.
    private static func commitCatalog(_ plan: UpdatePlan, context: ModelContext) throws -> CatalogMerge.Resolved {
        let resolved = try CatalogMerge.apply(
            plan.catalogPlan.catalog,
            images: plan.catalogPlan.images,
            weightCombos: plan.bundle.payload.weightCombos,
            context: context
        )

        var seenStepIDs: Set<UUID> = []
        let dedupedSteps = plan.bundle.payload.progressionSteps.filter { seenStepIDs.insert($0.id).inserted }
        ProgressionMerge.apply(
            plan.catalogPlan.catalog.progressions,
            steps: dedupedSteps,
            exercises: resolved.exercises,
            context: context
        )

        return resolved
    }

    /// The unlocked path: apply whichever differences the user left checked directly onto
    /// the workout they already have, so every session, tag and note pointing at it keeps
    /// working. Guarded by `!workout.isLocked` at the call site — see `WorkoutEditingService`
    /// for why locking is enforced there and not repeated as a throwing check here.
    static func applyInPlace(
        _ differences: [WorkoutDifference], to workout: Workout, plan: UpdatePlan, context: ModelContext
    ) throws {
        let resolved = try commitCatalog(plan, context: context)
        for difference in differences where difference.takeTheirs {
            difference.apply(resolved)
        }
        workout.sourceUpdatedAt = plan.bundle.sourceUpdatedAt
        workout.markDirty()
        try context.save()
    }

    /// The unlocked "keep both" path: an independent copy built the way a fresh
    /// download would, rather than merging in place. Since only one local copy should
    /// ever track a given publisher workout's future updates, the untouched original
    /// gives up that tracking here — the new copy is the one `FollowService
    /// .syncWorkoutUpdates` will match against from now on.
    static func saveAsCopy(_ plan: UpdatePlan, context: ModelContext) throws -> Workout {
        let resolved = try commitCatalog(plan, context: context)
        let workout = SharedWorkoutImporter.buildWorkout(
            from: plan.bundle.payload.workout,
            ownerRecordName: plan.bundle.ownerRecordName,
            sourceUpdatedAt: plan.bundle.sourceUpdatedAt,
            exercises: resolved.exercises,
            equipment: resolved.equipment,
            executionTypes: resolved.executionTypes,
            context: context
        )
        plan.workout.sourceOwnerRecordName = nil
        plan.workout.clonedFromWorkoutId = nil
        plan.workout.sourceUpdatedAt = nil
        plan.workout.markDirty()
        try context.save()
        return workout
    }

    /// The locked path: the same versioning `WorkoutCloningService.createNewVersion`
    /// gives a user's own edited workout, applied to an incoming publisher update
    /// instead of the workout's own current content. The update becomes the new active
    /// version; this copy becomes reachable from its version history instead of
    /// drifting out of sync with the publisher forever.
    static func saveAsNewVersion(_ plan: UpdatePlan, context: ModelContext) throws -> Workout {
        let resolved = try commitCatalog(plan, context: context)
        let original = plan.workout
        let groupID = original.versionGroupID ?? UUID()
        original.versionGroupID = groupID
        original.isSupersededVersion = true
        original.markDirty()

        let newVersion = SharedWorkoutImporter.buildWorkout(
            from: plan.bundle.payload.workout,
            ownerRecordName: plan.bundle.ownerRecordName,
            sourceUpdatedAt: plan.bundle.sourceUpdatedAt,
            exercises: resolved.exercises,
            equipment: resolved.equipment,
            executionTypes: resolved.executionTypes,
            context: context
        )
        newVersion.versionGroupID = groupID
        ScheduledWorkoutService.repointFutureSchedules(from: original, to: newVersion, context: context)
        try context.save()
        return newVersion
    }
}
