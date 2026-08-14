import Foundation
import SwiftData

/// One-time backfill: every existing Time section gets a "Get Ready" step inserted at
/// the front if it doesn't already have one — new sections get theirs automatically at
/// creation (`WorkoutEditingService.addSection`), but sections created before this
/// feature shipped need it added retroactively.
enum GetReadyStepMigration {
    private static let migratedFlagKey = "migration.getReadyStepV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let sections = (try? context.fetch(FetchDescriptor<WorkoutSection>())) ?? []
        var didChange = false

        for section in sections where section.sectionType == .time && section.deletedAt == nil {
            var steps = section.sortedTimeSteps
            guard steps.first?.stepType != .getReady else { continue }

            let getReady = TimeSectionStep(section: section, sortOrder: 0, stepType: .getReady, exercise: nil, durationSeconds: 15)
            context.insert(getReady)
            steps.insert(getReady, at: 0)
            TimeSectionStep.resequence(steps)
            section.markDirty()
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
