import Foundation
import SwiftData

/// Brings a downloaded workout into this user's library.
///
/// Two rules separate this from `ArchiveImportService`, and both matter:
///
/// **Exercises resolve by name, not by id.** UUIDs are only meaningful inside one
/// person's store — two users' catalogs are seeded independently, so the same
/// "Bench Press" has a different id for each of them. Matching on normalized name is the
/// only identity that survives the trip. Anything genuinely absent is created as a custom
/// exercise, so a downloaded workout is always runnable.
///
/// **Downloads copy, never upsert.** The archive importer's newest-wins policy is right
/// for a backup and wrong here: re-downloading would mutate the recipient's copy, which
/// they may have edited or already trained (making it `isLocked`). Every structural row
/// gets a fresh UUID, exactly like `WorkoutCloningService`, so two downloads produce two
/// independent workouts.
@MainActor
enum SharedWorkoutImporter {

    // MARK: - Planning

    /// Works out what a download *would* do, without writing anything.
    ///
    /// Adding rows to someone's exercise catalog is not something to do silently, so the
    /// confirmation names every exercise that will be created before the user commits.
    static func plan(_ payload: SharedWorkoutPayload, context: ModelContext) throws -> SharedWorkoutPlan {
        let resolver = try ExerciseNameResolver(context: context)
        let referenced = referencedExerciseIDs(in: payload.workout)

        var matched: [String] = []
        var missing: [String] = []
        for exercise in payload.exercises where referenced.contains(exercise.id) {
            if resolver.exercise(named: exercise.name) != nil {
                matched.append(exercise.name)
            } else {
                missing.append(exercise.name)
            }
        }

        return SharedWorkoutPlan(
            payload: payload,
            matchedExerciseNames: matched.sorted(),
            newExerciseNames: missing.sorted()
        )
    }

    // MARK: - Import

    /// Creates the workout, plus any exercises it needs that this user doesn't have.
    @discardableResult
    static func importWorkout(_ plan: SharedWorkoutPlan, context: ModelContext) throws -> Workout {
        let payload = plan.payload
        var resolver = try ExerciseNameResolver(context: context)

        // Equipment first: a created exercise may want to reference it.
        var equipmentByPublisherID: [UUID: Equipment] = [:]
        let existingEquipment = try context.fetch(FetchDescriptor<Equipment>(predicate: #Predicate { $0.deletedAt == nil }))
        var equipmentByName = Dictionary(
            existingEquipment.map { (ExerciseNameResolver.normalize($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for dto in payload.equipment {
            let key = ExerciseNameResolver.normalize(dto.name)
            if let match = equipmentByName[key] {
                equipmentByPublisherID[dto.id] = match
                continue
            }
            let created = Equipment(
                name: dto.name,
                iconSymbolName: dto.iconSymbolName,
                isCustom: true,
                isAtHome: dto.isAtHome,
                isAtGym: dto.isAtGym,
                isWeighted: dto.isWeighted,
                preferredWeightUnit: dto.preferredWeightUnit
            )
            context.insert(created)
            equipmentByName[key] = created
            equipmentByPublisherID[dto.id] = created
        }

        // Then exercises, keyed by the publisher's id so the workout's references resolve.
        var exercisesByPublisherID: [UUID: Exercise] = [:]
        for dto in payload.exercises {
            if let match = resolver.exercise(named: dto.name) {
                exercisesByPublisherID[dto.id] = match
                continue
            }
            let created = Exercise(
                name: dto.name,
                label: dto.label,
                notes: dto.notes,
                videoURL: dto.videoURL,
                iconSymbolName: dto.iconSymbolName,
                imageAssetName: dto.imageAssetName,
                isCustom: true,
                allowsBodyweight: dto.allowsBodyweight,
                isOneSided: dto.isOneSided,
                defaultEquipmentName: dto.defaultEquipmentName
            )
            context.insert(created)
            resolver.register(created)
            exercisesByPublisherID[dto.id] = created
        }

        let workout = buildWorkout(
            from: payload.workout,
            exercises: exercisesByPublisherID,
            equipment: equipmentByPublisherID,
            context: context
        )

        try context.save()
        return workout
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

    /// Every exercise id the workout actually references, across all three section
    /// shapes. The payload may carry more than the workout uses; only these matter.
    private static func referencedExerciseIDs(in workout: ArchiveWorkout) -> Set<UUID> {
        var ids: Set<UUID> = []
        for section in workout.sections where section.deletedAt == nil {
            for step in section.timeSteps where step.deletedAt == nil {
                if let id = step.exerciseID { ids.insert(id) }
            }
            for entry in section.repExercises where entry.deletedAt == nil {
                if let id = entry.exerciseID { ids.insert(id) }
            }
            // Quick entries are easy to forget — `WorkoutImportService.ExerciseResolver`
            // omits them, so EMOM/AMRAP exercises go unvalidated there. Included here.
            for entry in section.quickExercises where entry.deletedAt == nil {
                if let id = entry.exerciseID { ids.insert(id) }
            }
        }
        return ids
    }
}

/// Matches exercises by name across two different users' catalogs.
///
/// Lifted from the private resolver inside `WorkoutImportService` — same normalize rule
/// (trim + lowercase, exact match first) — but mutable, so exercises created mid-import
/// are visible to later lookups in the same pass.
struct ExerciseNameResolver {
    private var byExactName: [String: Exercise]
    private var byNormalizedName: [String: Exercise]

    init(context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.deletedAt == nil }))
        byExactName = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        byNormalizedName = Dictionary(
            all.map { (Self.normalize($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func exercise(named name: String?) -> Exercise? {
        guard let name else { return nil }
        return byExactName[name] ?? byNormalizedName[Self.normalize(name)]
    }

    /// Adds a just-created exercise, so two references to the same missing name in one
    /// payload resolve to one new row rather than two duplicates.
    mutating func register(_ exercise: Exercise) {
        byExactName[exercise.name] = exercise
        byNormalizedName[Self.normalize(exercise.name)] = exercise
    }
}
