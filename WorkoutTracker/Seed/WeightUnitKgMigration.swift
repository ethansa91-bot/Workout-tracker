import Foundation

/// Switches the app-wide weight unit to kg once, on devices that already stored a unit
/// before kg became the default. Changing `AppSettings.weightUnit`'s fallback alone
/// wouldn't reach them — the fallback only applies when nothing has ever been stored,
/// and using the Settings picker at any point stores a value.
///
/// Safe for history: every `SetLog` snapshots the unit it was logged in, so past sets
/// keep displaying in their original unit. The picker in Settings still works normally,
/// and this never runs again once the flag is set.
enum WeightUnitKgMigration {
    private static let migratedFlagKey = "migration.weightUnitKgV1"

    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        AppSettings.weightUnit = "kg"
    }
}
