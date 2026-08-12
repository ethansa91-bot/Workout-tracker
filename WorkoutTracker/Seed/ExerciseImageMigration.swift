import Foundation
import SwiftData

/// One-time backfill: exercises already seeded/imported on-device before
/// `imageAssetName` existed get it filled in from `ExerciseImageMapping` by name —
/// fresh installs get it directly at seed/import time instead. Not synced — it's a
/// local-only reference photo derivable from the name on any device — so this just
/// sets the field directly, no `markDirty()`/remote push involved.
enum ExerciseImageMigration {
    private static let migratedFlagKey = "migration.exerciseImagesV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var didChange = false

        for exercise in exercises where exercise.imageAssetName == nil {
            guard let assetName = ExerciseImageMapping.assetName[exercise.name] else { continue }
            exercise.imageAssetName = assetName
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
