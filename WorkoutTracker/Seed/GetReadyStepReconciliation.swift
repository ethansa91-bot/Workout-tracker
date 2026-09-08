import Foundation
import SwiftData

/// Removes duplicate Get Ready steps left behind when `GetReadyStepMigration` raced
/// CloudKit's initial import on a device that hadn't yet synced down a section's real
/// Get Ready step. Ridden on `CatalogReconciliation`'s existing one-shot post-import
/// hook rather than its own — `CloudKitSyncMonitor.onImportCompleted` is a single
/// closure, and a second assignment would replace the first instead of running
/// alongside it.
enum GetReadyStepReconciliation {
    @MainActor
    static func run(context: ModelContext) {
        guard let sections = try? context.fetch(FetchDescriptor<WorkoutSection>()) else { return }
        var removed = 0

        for section in sections where section.sectionType == .time && section.deletedAt == nil {
            let steps = section.sortedTimeSteps
            let getReadySteps = steps.filter { $0.stepType == .getReady }
            guard getReadySteps.count > 1 else { continue }
            // Oldest wins, so every device independently agrees on the same survivor.
            let sorted = getReadySteps.sorted { $0.updatedAt < $1.updatedAt }
            let duplicateIDs = Set(sorted.dropFirst().map(\.persistentModelID))
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                removed += 1
            }
            TimeSectionStep.resequence(steps.filter { !duplicateIDs.contains($0.persistentModelID) })
            section.markDirty()
        }

        guard removed > 0 else { return }
        do {
            try context.save()
            print("GetReadyStepReconciliation: removed \(removed) duplicate Get Ready steps")
        } catch {
            print("GetReadyStepReconciliation: save failed: \(error)")
        }
    }
}
