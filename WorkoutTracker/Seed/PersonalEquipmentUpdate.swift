import Foundation
import SwiftData

/// One-time follow-up to `PersonalExerciseImport`/`ExerciseReviewFavoritesImport`,
/// adding the user's actual owned equipment (with available weight increments) and
/// correcting exercise equipment to match what they really train with, rather than
/// wger's generic default or a heuristic guess made at import time.
enum PersonalEquipmentUpdate {
    private static let migratedFlagKey = "migration.personalEquipmentUpdateV1"

    private struct NewEquipment {
        let name: String
        let unit: String?
        let weights: [Double]
    }

    /// Equipment with no fixed weight (support apparatus, resistance is bodyweight
    /// or added via a vest/belt tracked separately) don't need combos.
    private static let newEquipmentWithoutWeights = ["Parallel Bars", "Parallettes", "Preacher Bench"]

    private static let newEquipmentWithWeights: [NewEquipment] = [
        NewEquipment(name: "Discs", unit: "lb", weights: [2.5, 5, 10, 25]),
        NewEquipment(name: "Mini Loop Resistance", unit: nil, weights: [1, 2, 3, 4, 5]),
        NewEquipment(name: "Weight vest", unit: "kg", weights: [2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20, 22.5, 25]),
        NewEquipment(name: "Weight belt", unit: "lb", weights: [5, 10, 15, 20, 25, 30, 35, 40, 50, 55, 60, 65, 70, 75, 80, 85, 90]),
    ]

    /// Weight increments for equipment that already exists in the catalog but has
    /// no combos seeded yet.
    private static let existingEquipmentWeights: [String: (unit: String?, weights: [Double])] = [
        "SZ-Bar": ("lb", [5, 10, 15, 20, 25, 30, 35, 40, 50, 55, 60, 65, 70, 75, 80, 85, 90]),
        "Barbell": ("lb", [5, 10, 15, 20, 25, 30, 35, 40, 50, 55, 60, 65, 70, 75, 80, 85, 90]),
        "Dumbbell": ("kg", [2.5, 3.5, 4.5, 5.5, 6.5, 8, 9, 10, 11.5, 13.5, 16, 18, 20.5, 22.5, 24]),
        "Resistance band": (nil, [1, 2, 3, 4, 5]),
    ]

    /// Exact exercise name (post-merge canonical name where applicable) -> equipment
    /// override. `nil` means bodyweight (clears any existing equipment). A few of
    /// these are wger catalog exercises whose name collided with one of the user's
    /// personal exercises at import time, which meant their label/equipment override
    /// never got applied (`PersonalExerciseImport` short-circuited on the name match).
    private static let equipmentOverrides: [(name: String, equipment: String?, label: String?)] = [
        ("Floor dips", "Weight vest", nil),
        ("Skullcrusher SZ-bar", "SZ-Bar", nil),
        ("Dips", "Weight vest", nil),
        ("TRX Rows", "TRX", nil),
        ("Ring Row (Inverted Row)", "Weight vest", nil),
        ("Pull-ups", "Weight vest", nil),
        ("Push-Up", "Weight vest", "Push ups"),
        ("Double Leg Calf Raise", "Weight vest", nil),
        ("Dumbbell Concentration Curl", "Dumbbell", "Concentración curl"),
        ("Banded Clamshell", "Resistance band", "Banded clamshell"),
        ("Arnold Shoulder Press", "Dumbbell", nil),
    ]

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        removeDuplicateArnoldPress(context: context)

        var equipmentByName = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Equipment>())) ?? []).map { ($0.name, $0) }
        )

        for name in newEquipmentWithoutWeights where equipmentByName[name] == nil {
            let equipment = Equipment(name: name, iconSymbolName: IconSymbolMapping.defaultEquipmentSymbol)
            context.insert(equipment)
            equipmentByName[name] = equipment
        }

        for spec in newEquipmentWithWeights {
            let equipment: Equipment
            if let existing = equipmentByName[spec.name] {
                equipment = existing
            } else {
                equipment = Equipment(name: spec.name, iconSymbolName: IconSymbolMapping.defaultEquipmentSymbol)
                context.insert(equipment)
                equipmentByName[spec.name] = equipment
            }
            addWeightCombos(spec.weights, unit: spec.unit, to: equipment, context: context)
        }

        for (name, spec) in existingEquipmentWeights {
            guard let equipment = equipmentByName[name] else { continue }
            addWeightCombos(spec.weights, unit: spec.unit, to: equipment, context: context)
        }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exercisesByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })

        for override in equipmentOverrides {
            guard let exercise = exercisesByName[override.name] else { continue }
            var didChange = false
            let newEquipment = override.equipment.flatMap { equipmentByName[$0] }
            if exercise.equipment?.id != newEquipment?.id {
                exercise.equipment = newEquipment
                didChange = true
            }
            if let label = override.label, exercise.label == nil {
                exercise.label = label
                didChange = true
            }
            if didChange {
                exercise.markDirty()
            }
        }

        try? context.save()
    }

    private static func addWeightCombos(_ values: [Double], unit: String?, to equipment: Equipment, context: ModelContext) {
        guard equipment.weightCombos.filter({ $0.deletedAt == nil }).isEmpty else { return }
        if let unit {
            equipment.preferredWeightUnit = unit
        }
        for (index, value) in values.enumerated() {
            let combo = WeightCombo(equipment: equipment, value: value, sortOrder: index)
            context.insert(combo)
        }
        equipment.markDirty()
    }

    /// `PersonalExerciseImport` originally included "Arnold Press" as a new custom
    /// exercise, not realizing it was already covered by
    /// `WgerCatalogMigration.legacyExerciseMergeMap` (merged into "Arnold Shoulder
    /// Press" before `PersonalExerciseImport` ever ran). That created a duplicate on
    /// any device that already ran the old version of the migration.
    private static func removeDuplicateArnoldPress(context: ModelContext) {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Arnold Press" && $0.isCustom })
        descriptor.fetchLimit = 1
        guard let duplicate = try? context.fetch(descriptor).first else { return }
        SyncDeletion.delete(duplicate, context: context)
    }
}
