import Foundation
import SwiftData

/// Loads the whole starter catalog — muscles, equipment, and exercises, already
/// merged/curated (labels, favorites, equipment assignments, everything) — from one
/// consolidated `catalog.json`, on a genuinely fresh install only. Replaces the old
/// multi-step seed/import/correction pipeline (`SeedDataLoader` + `WgerCatalogMigration`
/// + `WgerCatalogCorrection` + `WgerCategoryRevert` + `WgerNoPhotoCleanup` +
/// `FavoriteExercisesImport`/`Correction` + `PersonalExerciseImport` +
/// `ExerciseReviewFavoritesImport` + `PersonalEquipmentUpdate`, all of which still run,
/// unchanged, for a device that already has data from before this loader existed —
/// see the branch in `WorkoutTrackerApp.init()`.
///
/// Going forward, the catalog is a single source of truth: edit `catalog.json` directly
/// rather than adding another one-time migration file.
enum CatalogSeedLoader {
    static func seedIfNeeded(context: ModelContext) {
        guard !SeedDataLoader.hasSeeded else { return }
        do {
            let catalog: Catalog = try loadJSON("catalog")

            let muscleCategoriesByName = seedMuscleCategories(context: context)
            let exerciseCategoriesByName = seedExerciseCategories(context: context)
            let musclesByName = seedMuscles(catalog.muscles, categoriesByName: muscleCategoriesByName, context: context)
            let equipmentByName = seedEquipment(catalog.equipment, context: context)
            seedExercises(catalog.exercises, musclesByName: musclesByName, equipmentByName: equipmentByName, categoriesByName: exerciseCategoriesByName, context: context)

            try context.save()
            UserDefaults.standard.set(true, forKey: SeedDataLoader.seededFlagKey)
        } catch {
            print("CatalogSeedLoader: load failed: \(error)")
        }
    }

    // MARK: - JSON schema

    private struct Catalog: Decodable {
        let muscles: [MuscleEntry]
        let equipment: [EquipmentEntry]
        let exercises: [ExerciseEntry]
    }

    private struct MuscleEntry: Decodable {
        let name: String
        let categories: [String]
    }

    private struct EquipmentEntry: Decodable {
        let name: String
        let icon: String
        let isCustom: Bool
        let isAtHome: Bool
        let isAtGym: Bool
        let weighted: Bool
        let unit: String?
        let weights: [Double]
    }

    private struct ExerciseEntry: Decodable {
        let name: String
        let label: String?
        let notes: String?
        let icon: String
        let isCustom: Bool
        let isFavorited: Bool
        let equipment: [String]
        let muscles: [String]
        let categories: [String]
    }

    // MARK: - Fixed taxonomy (same lists as SeedDataLoader/WgerCategoryRevert)

    private static let fixedMuscleCategoryNames = ["upperBody", "core", "lowerBody"]
    private static let fixedExerciseCategoryNames = ["calisthenics", "strength", "mobility", "plyo", "cardio", "warmups", "physio"]

    private static func seedMuscleCategories(context: ModelContext) -> [String: MuscleCategory] {
        var result: [String: MuscleCategory] = [:]
        for name in fixedMuscleCategoryNames {
            let category = MuscleCategory(id: SeedIdentity.uuid("muscleCategory", name), name: name)
            context.insert(category)
            result[name] = category
        }
        return result
    }

    private static func seedExerciseCategories(context: ModelContext) -> [String: ExerciseCategory] {
        var result: [String: ExerciseCategory] = [:]
        for name in fixedExerciseCategoryNames {
            let category = ExerciseCategory(id: SeedIdentity.uuid("exerciseCategory", name), name: name)
            context.insert(category)
            result[name] = category
        }
        return result
    }

    // MARK: - Muscles

    private static func seedMuscles(_ entries: [MuscleEntry], categoriesByName: [String: MuscleCategory], context: ModelContext) -> [String: Muscle] {
        var result: [String: Muscle] = [:]
        for entry in entries {
            let muscle = Muscle(id: SeedIdentity.uuid("muscle", entry.name), name: entry.name, iconSymbolName: SeedDataLoader.symbol(forMuscleCategories: entry.categories))
            muscle.categories = entry.categories.compactMap { categoriesByName[$0] }
            context.insert(muscle)
            result[entry.name] = muscle
        }
        return result
    }

    // MARK: - Equipment

    private static func seedEquipment(_ entries: [EquipmentEntry], context: ModelContext) -> [String: Equipment] {
        var result: [String: Equipment] = [:]
        for entry in entries {
            let equipment = Equipment(
                id: SeedIdentity.uuid("equipment", entry.name),
                name: entry.name,
                iconSymbolName: entry.icon,
                isCustom: entry.isCustom,
                isAtHome: entry.isAtHome,
                isAtGym: entry.isAtGym,
                isWeighted: entry.weighted,
                preferredWeightUnit: entry.unit
            )
            context.insert(equipment)
            for (index, value) in entry.weights.enumerated() {
                let combo = WeightCombo(equipment: equipment, value: value, sortOrder: index)
                context.insert(combo)
            }
            result[entry.name] = equipment
        }
        return result
    }

    // MARK: - Exercises

    private static func seedExercises(
        _ entries: [ExerciseEntry],
        musclesByName: [String: Muscle],
        equipmentByName: [String: Equipment],
        categoriesByName: [String: ExerciseCategory],
        context: ModelContext
    ) {
        for entry in entries {
            let exercise = Exercise(
                id: SeedIdentity.uuid("catalogExercise", entry.name),
                name: entry.name,
                label: entry.label,
                notes: entry.notes,
                iconSymbolName: entry.icon,
                imageAssetName: ExerciseImageMapping.assetName[entry.name],
                isCustom: entry.isCustom,
                isFavorited: entry.isFavorited,
                equipmentItems: entry.equipment.compactMap { equipmentByName[$0] }
            )
            exercise.muscles = entry.muscles.compactMap { musclesByName[$0] }
            exercise.categories = entry.categories.compactMap { categoriesByName[$0] }
            context.insert(exercise)
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
