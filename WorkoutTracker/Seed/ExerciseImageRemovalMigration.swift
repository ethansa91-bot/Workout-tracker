import Foundation
import SwiftData

/// One-time cleanup: the free-exercise-db photos were removed and
/// `ExerciseImageMapping` cleared, but exercises already seeded/synced on-device
/// still hold `imageAssetName` values pointing at now-deleted asset names. This
/// nils those out so nothing references a missing image while a new source is
/// pending.
enum ExerciseImageRemovalMigration {
    private static let migratedFlagKey = "migration.exerciseImageRemovalV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var didChange = false

        for exercise in exercises where exercise.imageAssetName != nil {
            exercise.imageAssetName = nil
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
