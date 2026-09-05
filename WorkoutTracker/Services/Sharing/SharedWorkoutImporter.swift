import Foundation
import SwiftData

/// Brings a downloaded workout into this user's library.
///
/// Two rules separate this from `ArchiveImportService`, and both matter:
///
/// **Catalog rows resolve by identity, not by insertion.** Which local row an incoming
/// exercise, muscle or piece of equipment corresponds to — and what should happen when
/// they differ — is decided by `CatalogImportPlanner` and applied by `CatalogMerge`,
/// with the user's answer in between. Nothing here matches or creates catalog rows on
/// its own any more.
///
/// **Downloads copy, never upsert.** The archive importer's newest-wins policy is right
/// for a backup and wrong here: re-downloading would mutate the recipient's copy, which
/// they may have edited or already trained (making it `isLocked`). Every *structural* row
/// — the workout, its sections, steps and entries — gets a fresh UUID, exactly like
/// `WorkoutCloningService`, so two downloads produce two independent workouts.
@MainActor
enum SharedWorkoutImporter {

    // MARK: - Planning

    /// Works out what saving these workouts *would* do, without writing anything.
    ///
    /// One plan covers however many workouts were selected, because their catalogs are
    /// resolved together — see `CatalogImportPlanner.plan(_:context:)`.
    static func plan(_ bundles: [SharedWorkoutBundle], context: ModelContext) throws -> SharedWorkoutPlan {
        SharedWorkoutPlan(
            bundles: bundles,
            catalog: try CatalogImportPlanner.plan(bundles, context: context)
        )
    }

    // MARK: - Import

    /// Applies the catalog decisions **once**, then builds every workout against what
    /// they resolved to, in a single save.
    @discardableResult
    static func importWorkouts(_ plan: SharedWorkoutPlan, context: ModelContext) throws -> [Workout] {
        let resolved = try CatalogMerge.apply(
            plan.catalog,
            images: plan.images,
            weightCombos: plan.bundles.flatMap(\.payload.weightCombos),
            context: context
        )

        // After `CatalogMerge`, because it needs to know where each incoming exercise
        // landed — and before the workouts are built, so a runner opening one straight
        // away sees the ladder it expects.
        //
        // Once, over every bundle's rungs folded together: the decisions are global, so
        // applying them per bundle would run the same one repeatedly whenever two
        // downloaded workouts share a ladder — tearing down and rebuilding it each time.
        ProgressionMerge.apply(
            plan.catalog.progressions,
            steps: dedupedByID(plan.bundles.flatMap(\.payload.progressionSteps)),
            exercises: resolved.exercises,
            context: context
        )

        let workouts = plan.bundles.map { bundle in
            buildWorkout(
                from: bundle.payload.workout,
                ownerRecordName: bundle.ownerRecordName,
                sourceUpdatedAt: bundle.sourceUpdatedAt,
                exercises: resolved.exercises,
                equipment: resolved.equipment,
                executionTypes: resolved.executionTypes,
                context: context
            )
        }

        try context.save()
        return workouts
    }

    // MARK: - Building

    /// Publisher ids are stable within one download, so the same rung arriving in two
    /// bundles is the same rung.
    private static func dedupedByID(_ steps: [ArchiveProgressionStep]) -> [ArchiveProgressionStep] {
        var seen: Set<UUID> = []
        return steps.filter { seen.insert($0.id).inserted }
    }

    /// Only keeps an execution type the local exercise actually carries — the same
    /// capability guard the equipment and bodyweight options get, and for the same reason:
    /// the local exercise may be one the user chose to keep unchanged, so a payload must
    /// never select something its own pickers won't offer.
    private static func resolvedExecutionType(
        _ id: UUID?, for exercise: Exercise?, in executionTypes: [UUID: ExecutionType]
    ) -> ExecutionType? {
        guard let id, let type = executionTypes[id],
              exercise?.executionTypes.contains(where: { $0.id == type.id }) == true
        else { return nil }
        return type
    }

    /// The same capability guard `tracksSides` gets just below: a side only survives
    /// import when the local exercise is actually marked one-sided.
    private static func resolvedSide(_ raw: String?, for exercise: Exercise?) -> SetSide? {
        guard exercise?.isOneSided == true else { return nil }
        return raw.flatMap(SetSide.init(rawValue:))
    }

    /// Not `private`: `WorkoutUpdateService.saveAsCopy` calls this directly for the
    /// "locked, so only a new copy can be saved" path, reusing the exact same
    /// construction a fresh download goes through rather than a second implementation.
    static func buildWorkout(
        from dto: ArchiveWorkout,
        ownerRecordName: String,
        sourceUpdatedAt: Date,
        exercises: [UUID: Exercise],
        equipment: [UUID: Equipment],
        executionTypes: [UUID: ExecutionType],
        context: ModelContext
    ) -> Workout {
        // Fresh id, and `clonedFromWorkoutId` stamped with the publisher's — the field
        // already exists for exactly this kind of provenance.
        let workout = Workout(name: dto.name, notes: dto.notes, clonedFromWorkoutId: dto.id)
        // Who this came from and when they'd last published it — what
        // `FollowService.syncWorkoutUpdates` compares against on a later foreground
        // sweep to notice the publisher has moved on since this copy was made.
        workout.sourceOwnerRecordName = ownerRecordName
        workout.sourceUpdatedAt = sourceUpdatedAt
        context.insert(workout)

        for sectionDTO in dto.sections.sorted(by: { $0.sortOrder < $1.sortOrder })
        where sectionDTO.deletedAt == nil {
            buildSection(
                from: sectionDTO,
                into: workout,
                exercises: exercises,
                equipment: equipment,
                executionTypes: executionTypes,
                context: context
            )
        }

        return workout
    }

    /// One section, built fresh from its DTO and inserted at the end of `workout`'s
    /// sections list. Broken out of `buildWorkout`'s loop so `WorkoutDifferenceCalculator`
    /// can build a single section this same way when an update adds one to a workout the
    /// follower already has — a divergent second implementation is exactly how that path
    /// and a fresh download would drift apart.
    @discardableResult
    static func buildSection(
        from sectionDTO: ArchiveSection,
        into workout: Workout,
        exercises: [UUID: Exercise],
        equipment: [UUID: Equipment],
        executionTypes: [UUID: ExecutionType],
        context: ModelContext
    ) -> WorkoutSection {
        let section = WorkoutSection(
            workout: workout,
            sortOrder: sectionDTO.sortOrder,
            sectionType: WorkoutSectionType(rawValue: sectionDTO.sectionTypeRaw) ?? .time,
            name: sectionDTO.name,
            description: sectionDTO.sectionDescription
        )
        section.sourceSectionId = sectionDTO.id
        section.emomRoundCount = sectionDTO.emomRoundCount
        section.amrapDurationSeconds = sectionDTO.amrapDurationSeconds
        section.autostart = sectionDTO.autostart
        section.repeatCount = sectionDTO.repeatCount
        section.getReadySeconds = sectionDTO.getReadySeconds ?? 0
        section.repeatsGetReadyEachPass = sectionDTO.repeatsGetReadyEachPass ?? true
        section.sectionRestSeconds = sectionDTO.sectionRestSeconds ?? 0
        section.emomToFailure = sectionDTO.emomToFailure ?? false
        section.tracksRecord = sectionDTO.tracksRecord ?? false
        // The record identity travels so everyone running the publisher's benchmark
        // files under one name; the records themselves never leave the device, so the
        // recipient starts an empty history against it rather than inheriting one.
        section.recordGroupID = sectionDTO.recordGroupID
        // Deliberately *not* carried. A lock is earned by having done the work, and
        // the recipient hasn't — arriving pre-locked would leave them unable to edit a
        // section they have never run.
        section.recordLockedAt = nil
        context.insert(section)

        for stepDTO in sectionDTO.timeSteps.sorted(by: { $0.sortOrder < $1.sortOrder })
        where stepDTO.deletedAt == nil {
            buildTimeStep(from: stepDTO, into: section, exercises: exercises, equipment: equipment, executionTypes: executionTypes, context: context)
        }

        for repDTO in sectionDTO.repExercises.sorted(by: { $0.sortOrder < $1.sortOrder })
        where repDTO.deletedAt == nil {
            buildRepExercise(from: repDTO, into: section, exercises: exercises, equipment: equipment, executionTypes: executionTypes, context: context)
        }

        for quickDTO in sectionDTO.quickExercises.sorted(by: { $0.sortOrder < $1.sortOrder })
        where quickDTO.deletedAt == nil {
            buildQuickExercise(from: quickDTO, into: section, exercises: exercises, executionTypes: executionTypes, context: context)
        }

        return section
    }

    @discardableResult
    static func buildTimeStep(
        from stepDTO: ArchiveTimeStep,
        into section: WorkoutSection,
        exercises: [UUID: Exercise],
        equipment: [UUID: Equipment],
        executionTypes: [UUID: ExecutionType],
        context: ModelContext
    ) -> TimeSectionStep {
        let step = TimeSectionStep(
            section: section,
            sortOrder: stepDTO.sortOrder,
            stepType: TimeStepType(rawValue: stepDTO.stepTypeRaw) ?? .exercise,
            exercise: stepDTO.exerciseID.flatMap { exercises[$0] },
            durationSeconds: stepDTO.durationSeconds
        )
        step.sourceStepId = stepDTO.id
        step.colorRaw = stepDTO.colorRaw
        step.executionType = resolvedExecutionType(
            stepDTO.executionTypeID, for: step.exercise, in: executionTypes
        )
        step.side = resolvedSide(stepDTO.sideRaw, for: step.exercise)
        // Same membership guard the rep entry gets just below: a payload can't
        // select equipment the local exercise doesn't carry as a weighted option.
        if let equipmentID = stepDTO.preferredEquipmentID,
           let item = equipment[equipmentID],
           step.exercise?.equipmentItems.contains(where: { $0.id == item.id && $0.isWeighted }) == true {
            step.preferredEquipment = item
        }
        step.prefersBodyweight = (stepDTO.prefersBodyweight ?? false)
            && (step.exercise?.allowsBodyweightSource ?? false)
        context.insert(step)
        return step
    }

    @discardableResult
    static func buildRepExercise(
        from repDTO: ArchiveRepExercise,
        into section: WorkoutSection,
        exercises: [UUID: Exercise],
        equipment: [UUID: Equipment],
        executionTypes: [UUID: ExecutionType],
        context: ModelContext
    ) -> RepSectionExercise {
        let exercise = repDTO.exerciseID.flatMap { exercises[$0] }
        let entry = RepSectionExercise(
            section: section,
            sortOrder: repDTO.sortOrder,
            exercise: exercise,
            targetSets: repDTO.targetSets,
            customRestSeconds: repDTO.customRestSeconds,
            trackingMode: RepExerciseTrackingMode(rawValue: repDTO.trackingModeRaw) ?? .repsWeight,
            headStartSeconds: repDTO.headStartSeconds
        )
        entry.sourceRepExerciseId = repDTO.id
        // The same capability guards the archive importer applies, and they matter
        // more here: this data came from another user's device, so a payload must
        // never enable an option the local exercise doesn't actually support.
        // They matter more still now that the local exercise may be one the user
        // chose to keep unchanged rather than one this import created.
        entry.allowsBodyweight = repDTO.allowsBodyweight && (exercise?.allowsBodyweight ?? false)
        entry.tracksSides = repDTO.tracksSides && (exercise?.isOneSided ?? false)
        if let equipmentID = repDTO.preferredEquipmentID,
           let resolved = equipment[equipmentID],
           exercise?.equipmentItems.contains(where: { $0.id == resolved.id && $0.isWeighted }) == true {
            entry.preferredEquipment = resolved
        }
        entry.prefersBodyweight = repDTO.prefersBodyweight && (exercise?.allowsBodyweightSource ?? false)
        entry.executionType = resolvedExecutionType(
            repDTO.executionTypeID, for: exercise, in: executionTypes
        )
        entry.progressionEnabled = repDTO.progressionEnabled
        context.insert(entry)
        return entry
    }

    @discardableResult
    static func buildQuickExercise(
        from quickDTO: ArchiveQuickExercise,
        into section: WorkoutSection,
        exercises: [UUID: Exercise],
        executionTypes: [UUID: ExecutionType],
        context: ModelContext
    ) -> SectionExerciseEntry {
        let exercise = quickDTO.exerciseID.flatMap { exercises[$0] }
        let entry = SectionExerciseEntry(
            section: section,
            sortOrder: quickDTO.sortOrder,
            exercise: exercise,
            executionType: resolvedExecutionType(
                quickDTO.executionTypeID, for: exercise, in: executionTypes
            ),
            targetReps: quickDTO.targetReps
        )
        entry.sourceEntryId = quickDTO.id
        entry.side = resolvedSide(quickDTO.sideRaw, for: exercise)
        context.insert(entry)
        return entry
    }
}
