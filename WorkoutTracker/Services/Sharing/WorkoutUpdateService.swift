import Foundation
import SwiftData

/// Turns "this followed workout has a pending update" into either a merged-in-place
/// workout or a fresh copy, the two outcomes `WorkoutUpdateReviewView` offers.
///
/// Same shape as a fresh download (`FollowedUserDetailView.prepareDownload` →
/// `SharedWorkoutImporter`) because it *is* that path up to a point — download, resolve
/// the catalog — and only diverges once there's a `Workout` to compare against instead of
/// only ever a `Workout` to create. The one rule that matters throughout: nothing before
/// `applyInPlace`/`saveAsCopy` ever writes to the store. `preparePlan` only downloads and
/// plans (`CatalogImportPlanner.plan`, itself read-only); `computeDiff` only reads. Commit
/// — `CatalogMerge.apply`, which does write — happens exactly once, inside whichever of
/// the two final actions the user actually picks, so backing out of the review (or the
/// catalog sub-review `SharedImportReviewView` might show first) never leaves behind a
/// catalog row nobody asked for.
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

    /// The locked path: today's "Save Again," building an independent copy the way a
    /// fresh download would rather than touching the workout a session has already used.
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
        try context.save()
        return workout
    }
}
