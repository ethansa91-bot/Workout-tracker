import Foundation
import SwiftData

/// One-time replacement of the whole exercise/equipment/muscle/category catalog with
/// data imported from wger.de's open exercise database (CC-BY-SA), including photos.
/// A fresh install seeds this data directly via `SeedDataLoader` (the bundled
/// `SeedData/*.json` files were regenerated from wger) — this migration only does real
/// work on a device that already seeded the old, hand-curated catalog.
///
/// Three exercises ("90/90 Hip Stretch", "Barbell Back Squat", "Arnold Press") were
/// wired into real workout blocks and personal records on this device. Two of them
/// turned out to have a real wger equivalent under a different name, so their old row
/// is merged into the matching new one (block/record/log references get repointed,
/// old row deleted); "90/90 Hip Stretch" has no wger equivalent and is just deleted,
/// same as any other unmatched legacy exercise — see `legacyExerciseMergeMap`.
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
    /// blocks, personal records, set logs) get repointed to the new row before the
    /// old one is deleted, so nothing orphans.
    private static let legacyExerciseMergeMap: [String: String] = [
        "Arnold Press": "Arnold Shoulder Press",
        "Barbell Back Squat": "Barbell Full Squat",
    ]

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        guard
            let muscleSeeds: [MuscleSeed] = try? loadJSON("muscles"),
            let equipmentSeeds: [EquipmentSeed] = try? loadJSON("equipment"),
            let exerciseSeeds: [ExerciseSeed] = try? loadJSON("exercises")
        else { return }

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
                equipment: equipment
            )
            exercise.muscles = seed.muscles.compactMap { musclesByName[$0] }
            exercise.categories = seed.categories.compactMap { categoriesByName[$0] }
            context.insert(exercise)
            newByName[seed.name] = exercise
        }

        for old in existing {
            if let mergeTargetName = legacyExerciseMergeMap[old.name], let replacement = newByName[mergeTargetName] {
                relinkReferences(from: old, to: replacement, context: context)
            }
            SyncDeletion.delete(old, context: context)
        }
    }

    /// Repoints every workout block, personal record, and set log referencing `old`
    /// to `replacement` instead, so merging a legacy exercise into its wger
    /// equivalent doesn't orphan anything currently using it.
    private static func relinkReferences(from old: Exercise, to replacement: Exercise, context: ModelContext) {
        let repBlockExercises = (try? context.fetch(FetchDescriptor<RepBlockExercise>())) ?? []
        for row in repBlockExercises where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let timeBlockSteps = (try? context.fetch(FetchDescriptor<TimeBlockStep>())) ?? []
        for row in timeBlockSteps where row.exercise?.id == old.id {
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
