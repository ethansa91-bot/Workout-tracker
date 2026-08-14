import Foundation
import SwiftData

/// Backfills `Exercise.equipmentItems` (the new many-to-many equipment relationship)
/// from the deprecated single-equipment `Exercise.equipment` field.
enum ExerciseEquipmentMigration {
    private static let migratedFlagKey = "migration.exerciseEquipmentV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var didChange = false
        for exercise in exercises {
            guard exercise.equipmentItems.isEmpty, let legacy = exercise.equipment else { continue }
            exercise.equipmentItems = [legacy]
            exercise.markDirty()
            didChange = true
        }
        if didChange { try? context.save() }
    }
}
