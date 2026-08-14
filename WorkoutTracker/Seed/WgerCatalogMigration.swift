import Foundation
import SwiftData

/// One-time replacement of the whole exercise/equipment/muscle/category catalog with
/// data imported from wger.de's open exercise database (CC-BY-SA), including photos.
/// A fresh install seeds this data directly via `SeedDataLoader` (the bundled
/// `SeedData/*.json` files were regenerated from wger) — this migration only does real
/// work on a device that already seeded the old, hand-curated catalog.
///
/// Only exercises listed in `legacyExerciseMergeMap` are touched: their references
/// (workout sections, personal records, set logs) get repointed to the matching new
/// wger row and the old row is deleted, with the old name preserved as the new row's
/// `label` when it differs. Anything not in the map — including a user's own custom
/// exercises — is left exactly as-is, coexisting alongside the new 266-exercise
/// catalog. Nothing is ever deleted just for being unmapped.
///
/// For muscles/equipment/categories, some new names coincide exactly with old ones
/// (e.g. "Barbell", "Biceps") — those rows are revived in place (fields updated, kept
/// alive) rather than deleted-then-reinserted, since both would otherwise land on the
/// same deterministic `SeedIdentity` id and collide on the unique `id` constraint. Any
/// existing row referencing a revived row keeps working automatically, since the
/// underlying row object never disappears.
enum WgerCatalogMigration {
    private static let migratedFlagKey = "migration.wgerCatalogV1"

    /// Old (pre-wger) exercise name -> the wger exercise it's actually the same
    /// movement as, just named differently. References on the old row (workout
    /// sections, personal records, set logs) get repointed to the new row before the
    /// old one is deleted, so nothing orphans.
    /// Internal (not private) so `WgerNoPhotoCleanup` can exempt these replacement
    /// targets from its no-photo deletion pass — a couple of them (e.g. "Arnold
    /// Shoulder Press") carry real relinked workout history but have no wger photo.
    static let legacyExerciseMergeMap: [String: String] = [
        "Arnold Press": "Arnold Shoulder Press",
        "Barbell Back Squat": "Barbell Full Squat",

        // Personal exercise -> matching wger catalog exercise, from the Exercise
        // Reviewer pass over the full 266-exercise catalog. Three personal names
        // matched two catalog exercises each ("Bench Dips", "Barbell Shoulder
        // Press", "Dumbbell Hammer Curl") — only the first-listed target absorbs
        // the merge; the second just ends up favorited with no relink/label.
        "Incline Reverse Fly": "Incline Bench Reverse Fly",
        "TRX Bicep Curl": "Biceps with TRX",
        "TRX Row": "TRX Rows",
        "Weighted Lunge": "Lunges",
        "Hollow Body Hold (Banana Hold)": "Hollow Hold",
        "Bench Dips": "Floor dips",
        "Roman Chair Hyperextension, Straight Spine (Arms Extended)": "Hyperextensions",
        "Dumbbell Romanian Deadlift": "Dumbbell Romanian Deadlift",
        "Calf Raise": "Double Leg Calf Raise",
        "Close-Grip Flat Dumbbell Press": "Dumbbell Hex Press",
        "Incline Dumbbell Curl (45°)": "Seated W Curl",
        "Ab Wheel Rollout": "Ab wheel",
        "Banded Glute Kickback": "rubber band glute kickback",
        "Standing Dumbbell Curl": "Biceps Curls With Dumbbell",
        "Bent-Over Barbell Row (90°)": "Bent Over Rowing",
        "Single-Arm Dumbbell Row (3-Point Stance)": "Bent Over Dumbbell Rows",
        "EZ Bar Curl": "Biceps Curls With SZ-bar",
        "Flat Bench Dumbbell Press": "Benchpress Dumbbells",
        "Parallel Bar Dips": "Dips",
        "Flat Bench Dumbbell Fly": "Fly With Dumbbells",
        "Alternating Dumbbell Front Raise": "Front Raises",
        "Dumbbell Hammer Curl": "Hammer Curls",
        "EZ Bar Skull Crusher": "Skullcrusher SZ-bar",
        "Standing Dumbbell Lateral Raise": "Lateral Raises",
        "Bent-Over Reverse Fly (Standing)": "Rear Delt Raises",
        "Pistol Squat": "Pistol Squat",
        "Seated Dumbbell Shoulder Press": "Shoulder Press, Dumbbells",
        "Barbell Shoulder Press": "Shoulder Press, Barbell",
        "Dumbbell Shrug": "Shrugs, Dumbbells",
        "EZ Bar Preacher Curl": "Preacher Curls",
        "Incline Dumbbell Press (45°)": "Incline Bench Press - Dumbbell",
    ]

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        guard
            let muscleSeeds: [MuscleSeed] = try? loadJSON("muscles"),
            let equipmentSeeds: [EquipmentSeed] = try? loadJSON("equipment"),
            let allExerciseSeeds: [ExerciseSeed] = try? loadJSON("exercises")
        else { return }

        // Only the ~266 wger exercises with a real photo are wanted in the catalog —
        // the rest of wger's 850-exercise export has no image, just a generic SF
        // Symbol, and was never part of what the Exercise Reviewer tool showed.
        let exerciseSeeds = allExerciseSeeds.filter { ExerciseImageMapping.assetName[$0.name] != nil }

        let musclesByName = migrateMuscles(context: context, seeds: muscleSeeds)
        let equipmentByName = migrateEquipment(context: context, seeds: equipmentSeeds)
        let categoriesByName = migrateExerciseCategories(context: context, seeds: exerciseSeeds)
        migrateExercises(
            context: context,
            seeds: exerciseSeeds,
            musclesByName: musclesByName,
            equipmentByName: equipmentByName,
            categoriesByName: categoriesByName
        )

        try? context.save()
    }

    // MARK: - Muscles

    private struct MuscleSeed: Decodable {
        let name: String
        let categories: [String]
    }

    private static func migrateMuscles(context: ModelContext, seeds: [MuscleSeed]) -> [String: Muscle] {
        let allMuscleCategories = (try? context.fetch(FetchDescriptor<MuscleCategory>())) ?? []
        let categoriesByName = Dictionary(uniqueKeysWithValues: allMuscleCategories.map { ($0.name, $0) })

        let existing = (try? context.fetch(FetchDescriptor<Muscle>())) ?? []
        let existingByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })

        var result: [String: Muscle] = [:]
        var keptIDs = Set<UUID>()

        for seed in seeds {
            let categories = seed.categories.compactMap { categoriesByName[$0] }
            let icon = SeedDataLoader.symbol(forMuscleCategories: seed.categories)
            let muscle: Muscle
            if let revived = existingByName[seed.name] {
                revived.iconSymbolName = icon
                revived.categories = categories
                revived.deletedAt = nil
                revived.markDirty()
                muscle = revived
            } else {
                muscle = Muscle(id: SeedIdentity.uuid("muscle", seed.name), name: seed.name, iconSymbolName: icon)
                muscle.categories = categories
                context.insert(muscle)
            }
            result[seed.name] = muscle
            keptIDs.insert(muscle.id)
        }

        for old in existing where !keptIDs.contains(old.id) {
            SyncDeletion.delete(old, context: context)
        }

        return result
    }

    // MARK: - Equipment

    private struct EquipmentSeed: Decodable {
        let name: String
        let icon: String
    }

    private static func migrateEquipment(context: ModelContext, seeds: [EquipmentSeed]) -> [String: Equipment] {
        let existing = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        let existingByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })

        var result: [String: Equipment] = [:]
        var keptIDs = Set<UUID>()

        for seed in seeds {
            let equipment: Equipment
            if let revived = existingByName[seed.name] {
                revived.iconSymbolName = seed.icon
                revived.deletedAt = nil
                revived.markDirty()
                equipment = revived
            } else {
                equipment = Equipment(id: SeedIdentity.uuid("equipment", seed.name), name: seed.name, iconSymbolName: seed.icon)
                context.insert(equipment)
            }
            result[seed.name] = equipment
            keptIDs.insert(equipment.id)
        }

        for old in existing where !keptIDs.contains(old.id) {
            SyncDeletion.delete(old, context: context)
        }

        return result
    }

    // MARK: - Exercise categories

    private static func migrateExerciseCategories(context: ModelContext, seeds: [ExerciseSeed]) -> [String: ExerciseCategory] {
        let names = Array(Set(seeds.flatMap { $0.categories })).sorted()

        let existing = (try? context.fetch(FetchDescriptor<ExerciseCategory>())) ?? []
        let existingByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })

        var result: [String: ExerciseCategory] = [:]
        var keptIDs = Set<UUID>()

        for name in names {
            let category: ExerciseCategory
            if let revived = existingByName[name] {
                revived.deletedAt = nil
                revived.markDirty()
                category = revived
            } else {
                category = ExerciseCategory(id: SeedIdentity.uuid("exerciseCategory", name), name: name)
                context.insert(category)
            }
            result[name] = category
            keptIDs.insert(category.id)
        }

        for old in existing where !keptIDs.contains(old.id) {
            SyncDeletion.delete(old, context: context)
        }

        return result
    }

    // MARK: - Exercises

    private struct ExerciseSeed: Decodable {
        let name: String
        let equipment: String?
        let muscles: [String]
        let categories: [String]
        let notes: String?
    }

    private static func migrateExercises(
        context: ModelContext,
        seeds: [ExerciseSeed],
        musclesByName: [String: Muscle],
        equipmentByName: [String: Equipment],
        categoriesByName: [String: ExerciseCategory]
    ) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        var newByName: [String: Exercise] = [:]
        for seed in seeds {
            let equipment = seed.equipment.flatMap { equipmentByName[$0] }
            let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: seed.categories)
            let exercise = Exercise(
                id: SeedIdentity.uuid("wgerExercise", seed.name),
                name: seed.name,
                notes: seed.notes,
                iconSymbolName: symbol,
                imageAssetName: ExerciseImageMapping.assetName[seed.name],
                equipmentItems: equipment.map { [$0] } ?? []
            )
            exercise.muscles = seed.muscles.compactMap { musclesByName[$0] }
            exercise.categories = seed.categories.compactMap { categoriesByName[$0] }
            context.insert(exercise)
            newByName[seed.name] = exercise
        }

        for old in existing {
            guard let mergeTargetName = legacyExerciseMergeMap[old.name],
                  let replacement = newByName[mergeTargetName] else { continue }
            relinkReferences(from: old, to: replacement, context: context)
            if replacement.label == nil, old.name != replacement.name {
                replacement.label = old.name
                replacement.markDirty()
            }
            SyncDeletion.delete(old, context: context)
        }
    }

    /// Repoints every workout section, personal record, and set log referencing `old`
    /// to `replacement` instead, so merging a legacy exercise into its wger
    /// equivalent doesn't orphan anything currently using it.
    private static func relinkReferences(from old: Exercise, to replacement: Exercise, context: ModelContext) {
        let repSectionExercises = (try? context.fetch(FetchDescriptor<RepSectionExercise>())) ?? []
        for row in repSectionExercises where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let timeSectionSteps = (try? context.fetch(FetchDescriptor<TimeSectionStep>())) ?? []
        for row in timeSectionSteps where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let personalRecords = (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for row in personalRecords where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let setLogs = (try? context.fetch(FetchDescriptor<SetLog>())) ?? []
        for row in setLogs where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }
    }

    // MARK: - JSON loading

    private static func loadJSON<T: Decodable>(_ resource: String) throws -> T {
        let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "SeedData")
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
        guard let url else { throw SeedDataError.missingResource(resource) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
