import Foundation
import SwiftData

/// One-time backfill: every existing Time block gets a "Get Ready" step inserted at
/// the front if it doesn't already have one — new blocks get theirs automatically at
/// creation (`WorkoutEditingService.addBlock`), but blocks created before this
/// feature shipped need it added retroactively.
enum GetReadyStepMigration {
    private static let migratedFlagKey = "migration.getReadyStepV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let blocks = (try? context.fetch(FetchDescriptor<WorkoutBlock>())) ?? []
        var didChange = false

        for block in blocks where block.blockType == .time && block.deletedAt == nil {
            var steps = block.sortedTimeSteps
            guard steps.first?.stepType != .getReady else { continue }

            let getReady = TimeBlockStep(block: block, sortOrder: 0, stepType: .getReady, exercise: nil, durationSeconds: 15)
            context.insert(getReady)
            steps.insert(getReady, at: 0)
            TimeBlockStep.resequence(steps)
            block.markDirty()
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
