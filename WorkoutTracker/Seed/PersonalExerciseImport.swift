import Foundation
import SwiftData

/// One-time import of the personal exercises from the Exercise Reviewer pass that
/// don't already have a matching wger catalog exercise (those 31 are handled instead
/// by `WgerCatalogMigration.legacyExerciseMergeMap`, which merges them into their
/// catalog equivalent). These ~90 are genuinely custom moves with no wger photo —
/// created as custom, favorited exercises with the user's own short nickname
/// preserved as `label`. Must run after `WgerCatalogMigration` so muscle/category
/// names resolve against the current wger-sourced taxonomy.
enum PersonalExerciseImport {
    private static let importedFlagKey = "import.personalExercisesV1"

    private struct Entry: Decodable {
        let name: String
        let label: String?
        let equipment: String?
        let muscles: [String]
        let categories: [String]
        let notes: String?
    }

    static func importIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: importedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: importedFlagKey) }

        guard let entries: [Entry] = try? loadJSON("personalExercises") else { return }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var existingByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name.lowercased(), $0) })

        let allMuscles = (try? context.fetch(FetchDescriptor<Muscle>())) ?? []
        let musclesByName = Dictionary(uniqueKeysWithValues: allMuscles.map { ($0.name, $0) })

        let allCategories = (try? context.fetch(FetchDescriptor<ExerciseCategory>())) ?? []
        let categoriesByName = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.name, $0) })

        var equipmentByName = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Equipment>())) ?? []).map { ($0.name, $0) }
        )

        for entry in entries {
            if let existing = existingByName[entry.name.lowercased()] {
                var didChangeExisting = false
                if !existing.isFavorited {
                    existing.isFavorited = true
                    didChangeExisting = true
                }
                if existing.label == nil, let label = entry.label {
                    existing.label = label
                    didChangeExisting = true
                }
                if existing.equipment == nil, let equipmentName = entry.equipment, let equipment = equipmentByName[equipmentName] {
                    existing.equipment = equipment
                    didChangeExisting = true
                }
                if didChangeExisting {
                    existing.markDirty()
                }
                continue
            }

            var equipment: Equipment?
            if let equipmentName = entry.equipment {
                if let found = equipmentByName[equipmentName] {
                    equipment = found
                } else {
                    let created = Equipment(name: equipmentName, iconSymbolName: IconSymbolMapping.defaultEquipmentSymbol)
                    context.insert(created)
                    equipmentByName[equipmentName] = created
                    equipment = created
                }
            }

            let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: entry.categories)
            let exercise = Exercise(
                name: entry.name,
                label: entry.label,
                notes: entry.notes,
                iconSymbolName: symbol,
                isCustom: true,
                isFavorited: true,
                equipment: equipment
            )
            exercise.muscles = entry.muscles.compactMap { musclesByName[$0] }
            exercise.categories = entry.categories.compactMap { categoriesByName[$0] }
            context.insert(exercise)
            existingByName[entry.name.lowercased()] = exercise
        }

        try? context.save()
    }

    private static func loadJSON<T: Decodable>(_ resource: String) throws -> T {
        let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "SeedData")
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
        guard let url else { throw SeedDataError.missingResource(resource) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
