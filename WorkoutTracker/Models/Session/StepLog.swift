import Foundation
import SwiftData

enum StepOutcome: String, Codable {
    case completed, skipped
}

/// Per-step outcome for a time section. Powers the horizontal scrub strip: a step that
/// was jumped over on the way forward gets a `.skipped` log; one actually run through
/// gets `.completed`.
@Model
final class StepLog: SyncableModel {
    @Attribute(.unique) var id: UUID
    var session: WorkoutSession?
    var timeSectionStep: TimeSectionStep?
    /// Display resilience if the underlying step is later edited/removed on a clone.
    var stepExerciseNameSnapshot: String?
    var plannedDurationSeconds: Int
    var actualDurationSeconds: Int
    var outcomeRaw: String
    var loggedAt: Date
    var sortOrder: Int
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    var outcome: StepOutcome {
        get { StepOutcome(rawValue: outcomeRaw) ?? .completed }
        set { outcomeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        session: WorkoutSession? = nil,
        timeSectionStep: TimeSectionStep? = nil,
        stepExerciseNameSnapshot: String? = nil,
        plannedDurationSeconds: Int,
        actualDurationSeconds: Int,
        outcome: StepOutcome,
        sortOrder: Int
    ) {
        self.id = id
        self.session = session
        self.timeSectionStep = timeSectionStep
        self.stepExerciseNameSnapshot = stepExerciseNameSnapshot
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.outcomeRaw = outcome.rawValue
        self.loggedAt = .now
        self.sortOrder = sortOrder
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
