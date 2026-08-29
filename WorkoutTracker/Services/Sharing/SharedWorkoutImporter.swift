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

        let workouts = plan.bundles.map { bundle in
            buildWorkout(
                from: bundle.payload.workout,
                exercises: resolved.exercises,
                equipment: resolved.equipment,
                context: context
            )
        }

        try context.save()
        return workouts
    }

    // MARK: - Building

    private static func buildWorkout(
        from dto: ArchiveWorkout,
        exercises: [UUID: Exercise],
        equipment: [UUID: Equipment],
        context: ModelContext
    ) -> Workout {
        // Fresh id, and `clonedFromWorkoutId` stamped with the publisher's — the field
        // already exists for exactly this kind of provenance.
        let workout = Workout(name: dto.name, notes: dto.notes, clonedFromWorkoutId: dto.id)
        context.insert(workout)

        for sectionDTO in dto.sections.sorted(by: { $0.sortOrder < $1.sortOrder })
        where sectionDTO.deletedAt == nil {
            let section = WorkoutSection(
                workout: workout,
                sortOrder: sectionDTO.sortOrder,
                sectionType: WorkoutSectionType(rawValue: sectionDTO.sectionTypeRaw) ?? .time,
                name: sectionDTO.name,
                description: sectionDTO.sectionDescription
            )
            section.emomRoundCount = sectionDTO.emomRoundCount
            section.amrapDurationSeconds = sectionDTO.amrapDurationSeconds
            section.autostart = sectionDTO.autostart
            section.repeatCount = sectionDTO.repeatCount
            context.insert(section)

            for stepDTO in sectionDTO.timeSteps.sorted(by: { $0.sortOrder < $1.sortOrder })
            where stepDTO.deletedAt == nil {
                let step = TimeSectionStep(
                    section: section,
                    sortOrder: stepDTO.sortOrder,
                    stepType: TimeStepType(rawValue: stepDTO.stepTypeRaw) ?? .exercise,
                    exercise: stepDTO.exerciseID.flatMap { exercises[$0] },
                    durationSeconds: stepDTO.durationSeconds
                )
                step.colorRaw = stepDTO.colorRaw
                context.insert(step)
            }

            for repDTO in sectionDTO.repExercises.sorted(by: { $0.sortOrder < $1.sortOrder })
            where repDTO.deletedAt == nil {
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
                context.insert(entry)
            }

            for quickDTO in sectionDTO.quickExercises.sorted(by: { $0.sortOrder < $1.sortOrder })
            where quickDTO.deletedAt == nil {
                let entry = SectionExerciseEntry(
                    section: section,
                    sortOrder: quickDTO.sortOrder,
                    exercise: quickDTO.exerciseID.flatMap { exercises[$0] }
                )
                context.insert(entry)
            }
        }

        return workout
    }
}
