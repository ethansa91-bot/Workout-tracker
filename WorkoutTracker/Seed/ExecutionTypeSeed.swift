import Foundation
import SwiftData

/// Creates the starter execution types — Explosive, Hold, Slow.
///
/// Deliberately its own migration rather than an entry in `catalog.json`: this must reach
/// devices that seeded their catalog long before execution types existed, and the seed
/// loader only ever runs on a genuinely fresh install. Called unconditionally from
/// `WorkoutTrackerApp.init()` for that reason, and its flag is **not** in
/// `legacyMigrationFlagKeys` — that list is for migrations a fresh install should skip.
///
/// Ids come from `SeedIdentity` so two devices seeding independently converge on the same
/// three rows instead of pushing six to CloudKit. `isCustom` stays false, which is what
/// tells these apart from anything the user adds from the exercise page.
enum ExecutionTypeSeed {
    private static let seededFlagKey = "seed.executionTypesV1"

    static let defaultNames = ["Explosive", "Hold", "Slow"]

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: seededFlagKey) }
        seed(context: context)
    }

    /// The work without the flag guard — `DataResetService` replays it after wiping the
    /// store, where the flag is already set and `seedIfNeeded` would do nothing.
    static func seed(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ExecutionType>())) ?? []
        let existingIDs = Set(existing.map(\.id))

        var didChange = false
        for name in defaultNames {
            let id = SeedIdentity.uuid("executionType", name)
            guard !existingIDs.contains(id) else { continue }
            context.insert(ExecutionType(id: id, name: name))
            didChange = true
        }
        if didChange { try? context.save() }
    }
}
