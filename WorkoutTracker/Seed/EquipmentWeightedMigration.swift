import Foundation
import SwiftData

/// Backfills `Equipment.isWeighted` for existing rows: any equipment that already has
/// weight values attached is clearly the "weighted" kind, regardless of catalog name —
/// freshly seeded catalog items get their `isWeighted` value directly from seed data
/// instead, so this only needs to touch equipment that predates the field.
enum EquipmentWeightedMigration {
    private static let migratedFlagKey = "migration.equipmentWeightedV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        var didChange = false
        for item in equipment where !item.isWeighted && !item.weightCombos.isEmpty {
            item.isWeighted = true
            item.markDirty()
            didChange = true
        }
        if didChange { try? context.save() }
    }
}
