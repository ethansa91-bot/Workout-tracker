import Foundation
import SwiftData

/// One-time backfill: `Equipment.isFavorited` ("In my equipment") is being replaced
/// by two independent flags, `isAtHome`/`isAtGym`. Existing favorited rows become
/// `isAtHome = true` — closest existing semantic, since the old toggle was about
/// personal possession rather than a specific commercial gym.
enum EquipmentHomeGymMigration {
    private static let migratedFlagKey = "migration.equipmentHomeGymV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        var didChange = false

        for item in equipment where item.isFavorited {
            item.isAtHome = true
            item.markDirty()
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
