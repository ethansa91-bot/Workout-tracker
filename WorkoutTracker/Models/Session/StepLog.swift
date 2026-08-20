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
    var id: UUID = UUID()
    var session: WorkoutSession?
    var timeSectionStep: TimeSectionStep?
    /// Display resilience if the underlying step is later edited/removed on a clone.
    var stepExerciseNameSnapshot: String?
    var plannedDurationSeconds: Int = 0
    var actualDurationSeconds: Int = 0
    var outcomeRaw: String = StepOutcome.completed.rawValue
    var loggedAt: Date = Date.now
    var sortOrder: Int = 0
    /// Which pass through a repeated section this log belongs to, 0-based. Without it
    /// the step reference alone is the identity, so a section run three times would
    /// record only its first pass.
    var repeatIndex: Int = 0
    var updatedAt: Date = Date.now
    var deletedAt: Date?

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
        sortOrder: Int,
        repeatIndex: Int = 0
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
        self.repeatIndex = repeatIndex
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
