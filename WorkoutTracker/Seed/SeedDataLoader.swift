import Foundation
import SwiftData

enum SeedDataError: Error {
    case missingResource(String)
}

/// Populates the starter catalog (muscles, equipment, exercises) on first launch only.
/// Everything seeded here starts `isDirty = true` / `remoteSyncedAt = nil` just like any
/// other locally-created row, so it flows through the normal "sync everything" path the
/// first time the user pushes to Supabase — no special-casing needed in the sync engine.
enum SeedDataLoader {
    private static let seededFlagKey = "seed.didSeedCatalogV1"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededFlagKey) else { return }
        do {
            let categoriesByName = seedMuscleCategories(context: context)
            let musclesByName = try seedMuscles(context: context, categoriesByName: categoriesByName)
            let equipmentByName = try seedEquipment(context: context)
            let exerciseCategoriesByName = seedExerciseCategories(context: context)
            try seedExercises(
                context: context,
                musclesByName: musclesByName,
                equipmentByName: equipmentByName,
                exerciseCategoriesByName: exerciseCategoriesByName
            )
            try context.save()
            UserDefaults.standard.set(true, forKey: seededFlagKey)
        } catch {
            print("Seed data load failed: \(error)")
        }
    }

    // MARK: - Muscle categories (fixed taxonomy, not JSON-driven)

    private static let fixedMuscleCategoryNames = ["upperBody", "core", "lowerBody"]

    private static func seedMuscleCategories(context: ModelContext) -> [String: MuscleCategory] {
        var result: [String: MuscleCategory] = [:]
        for name in fixedMuscleCategoryNames {
            let category = MuscleCategory(id: SeedIdentity.uuid("muscleCategory", name), name: name)
            context.insert(category)
            result[name] = category
        }
        return result
    }

    // MARK: - Exercise categories (fixed taxonomy, not JSON-driven)

    private static let fixedExerciseCategoryNames = ["calisthenics", "strength", "mobility", "plyo", "cardio", "warmups", "physio"]

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

    private struct MuscleSeed: Decodable {
        let name: String
        let categories: [String]
    }

    private static func seedMuscles(context: ModelContext, categoriesByName: [String: MuscleCategory]) throws -> [String: Muscle] {
        let seeds: [MuscleSeed] = try loadJSON("muscles")
        var result: [String: Muscle] = [:]
        for seed in seeds {
            let muscle = Muscle(id: SeedIdentity.uuid("muscle", seed.name), name: seed.name, iconSymbolName: symbol(forMuscleCategories: seed.categories))
            muscle.categories = seed.categories.compactMap { categoriesByName[$0] }
            context.insert(muscle)
            result[seed.name] = muscle
        }
        return result
    }

    static func symbol(forMuscleCategories categories: [String]) -> String {
        let set = Set(categories)
        if set.contains("lowerBody") { return "figure.walk" }
        if set.contains("core") { return "figure.core.training" }
        return IconSymbolMapping.defaultMuscleSymbol
    }

    // MARK: - Equipment

    private struct EquipmentSeed: Decodable {
        let name: String
        let icon: String
    }

    private static func seedEquipment(context: ModelContext) throws -> [String: Equipment] {
        let seeds: [EquipmentSeed] = try loadJSON("equipment")
        var result: [String: Equipment] = [:]
        for seed in seeds {
            let equipment = Equipment(id: SeedIdentity.uuid("equipment", seed.name), name: seed.name, iconSymbolName: seed.icon)
            context.insert(equipment)
            result[seed.name] = equipment
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

    private static func seedExercises(
        context: ModelContext,
        musclesByName: [String: Muscle],
        equipmentByName: [String: Equipment],
        exerciseCategoriesByName: [String: ExerciseCategory]
    ) throws {
        // Only the ~266 wger exercises with a real photo are wanted in the catalog —
        // the rest of wger's 850-exercise export has no image, just a generic SF
        // Symbol, and was never part of what the Exercise Reviewer tool showed.
        let allSeeds: [ExerciseSeed] = try loadJSON("exercises")
        let seeds = allSeeds.filter { ExerciseImageMapping.assetName[$0.name] != nil }
        for seed in seeds {
            let equipment = seed.equipment.flatMap { equipmentByName[$0] }
            let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: seed.categories)
            let exercise = Exercise(id: SeedIdentity.uuid("exercise", seed.name), name: seed.name, notes: seed.notes, iconSymbolName: symbol, imageAssetName: ExerciseImageMapping.assetName[seed.name], equipment: equipment)
            exercise.muscles = seed.muscles.compactMap { musclesByName[$0] }
            exercise.categories = seed.categories.compactMap { exerciseCategoriesByName[$0] }
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
