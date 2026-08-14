import Foundation
import SwiftData

/// Follow-up to `WgerCatalogMigration` for devices that already ran it while it still
/// used wger's own body-region category taxonomy (Abs, Arms, Back, Calves, Cardio,
/// Chest, Legs, Shoulders) — redundant with the muscle taxonomy already covering that
/// axis. Reverts to the original training-style taxonomy (calisthenics, strength,
/// mobility, plyo, cardio, warmups, physio), re-deriving each wger-sourced exercise's
/// categories from a keyword/equipment heuristic baked into the regenerated
/// `exercises.json` (see the migration script's `recategorize.py` for the exact rules).
/// A device migrating for the first time after this file existed never needs this:
/// `SeedDataLoader`/`WgerCatalogMigration` already read the reverted taxonomy directly
/// from `exercises.json`.
enum WgerCategoryRevert {
    private static let migratedFlagKey = "migration.wgerCategoryRevertV1"

    private struct ExerciseSeed: Decodable {
        let name: String
        let categories: [String]
    }

    static func revertIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        guard let seeds: [ExerciseSeed] = try? loadJSON("exercises") else { return }
        let seedsByName = Dictionary(uniqueKeysWithValues: seeds.map { ($0.name, $0) })

        let categoriesByName = revertCategories(context: context, names: seeds.flatMap { $0.categories })
        reassignExerciseCategories(context: context, seedsByName: seedsByName, categoriesByName: categoriesByName)

        try? context.save()
    }

    private static func revertCategories(context: ModelContext, names: [String]) -> [String: ExerciseCategory] {
        let uniqueNames = Array(Set(names)).sorted()

        let existing = (try? context.fetch(FetchDescriptor<ExerciseCategory>())) ?? []
        let existingByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })

        var result: [String: ExerciseCategory] = [:]
        var keptIDs = Set<UUID>()

        for name in uniqueNames {
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

    private static func reassignExerciseCategories(
        context: ModelContext,
        seedsByName: [String: ExerciseSeed],
        categoriesByName: [String: ExerciseCategory]
    ) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            guard let seed = seedsByName[exercise.name] else { continue }
            exercise.categories = seed.categories.compactMap { categoriesByName[$0] }
            exercise.iconSymbolName = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: seed.categories)
            exercise.markDirty()
        }
    }

    private static func loadJSON<T: Decodable>(_ resource: String) throws -> T {
        let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "SeedData")
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
        guard let url else { throw SeedDataError.missingResource(resource) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
