import Foundation
import SwiftData

/// One-time cleanup for devices where `WgerCatalogMigration` already ran before it
/// was scoped down to just the ~266 photographed wger exercises out of wger's full
/// 850-exercise export — removes any wger-sourced (non-custom) exercise that has no
/// photo, since those were never part of what the Exercise Reviewer tool showed and
/// just clutter the catalog. Exercises that absorbed real workout history via
/// `WgerCatalogMigration.legacyExerciseMergeMap` are kept regardless of photo, so
/// nothing gets re-orphaned. Must run after `WgerCatalogMigration`.
enum WgerNoPhotoCleanup {
    private static let migratedFlagKey = "migration.wgerNoPhotoCleanupV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let protectedNames = Set(WgerCatalogMigration.legacyExerciseMergeMap.values)
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var didChange = false

        for exercise in exercises {
            guard !exercise.isCustom, exercise.imageAssetName == nil, !protectedNames.contains(exercise.name) else { continue }
            SyncDeletion.delete(exercise, context: context)
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
