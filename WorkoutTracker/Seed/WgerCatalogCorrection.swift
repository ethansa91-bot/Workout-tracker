import Foundation
import SwiftData

/// Follow-up to `WgerCatalogMigration` for devices that already ran it before the
/// real wger equivalents for "Arnold Press" and "Barbell Back Squat" were known —
/// merges those two into their matching wger rows and deletes "90/90 Hip Stretch"
/// outright (no wger equivalent). A device migrating for the first time after this
/// file existed never needs this: `WgerCatalogMigration`'s own `legacyExerciseMergeMap`
/// already handles it in one pass.
enum WgerCatalogCorrection {
    private static let migratedFlagKey = "migration.wgerCatalogCorrectionV1"

    private static let mergeMap: [String: String] = [
        "Arnold Press": "Arnold Shoulder Press",
        "Barbell Back Squat": "Barbell Full Squat",
    ]
    private static let deleteOnlyNames: Set<String> = ["90/90 Hip Stretch"]

    static func correctIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })

        var didChange = false

        for (oldName, newName) in mergeMap {
            guard let old = byName[oldName], let replacement = byName[newName] else { continue }
            relinkReferences(from: old, to: replacement, context: context)
            SyncDeletion.delete(old, context: context)
            didChange = true
        }

        for name in deleteOnlyNames {
            guard let old = byName[name] else { continue }
            SyncDeletion.delete(old, context: context)
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }

    private static func relinkReferences(from old: Exercise, to replacement: Exercise, context: ModelContext) {
        let repBlockExercises = (try? context.fetch(FetchDescriptor<RepBlockExercise>())) ?? []
        for row in repBlockExercises where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let timeBlockSteps = (try? context.fetch(FetchDescriptor<TimeBlockStep>())) ?? []
        for row in timeBlockSteps where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let personalRecords = (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for row in personalRecords where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }

        let setLogs = (try? context.fetch(FetchDescriptor<SetLog>())) ?? []
        for row in setLogs where row.exercise?.id == old.id {
            row.exercise = replacement
            row.markDirty()
        }
    }
}
