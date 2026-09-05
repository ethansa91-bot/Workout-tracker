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
    /// How the step was performed. Stamped here rather than read back through
    /// `timeSectionStep`, for the same reason `SetLog` stamps its own: the plan can be
    /// edited or deleted after the fact, and history should keep saying what happened.
    /// Symmetric with `SetLog.executionType`, which the rep side already carries.
    var executionType: ExecutionType?
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

    /// What this log is called in history. Prefers the live step — so a renamed exercise
    /// reads correctly — and falls back to the snapshot when the step is gone, which is
    /// the case the snapshot exists for.
    var displayTitle: String {
        if let step = timeSectionStep {
            // The step's own title already handles Rest and Get Ready, which have no
            // exercise and no type.
            guard step.stepType == .exercise else { return step.displayTitle }
            return ExerciseNaming.title(step.exercise, executionType: executionType ?? step.executionType)
        }
        return ExerciseNaming.title(stepExerciseNameSnapshot ?? "Rest", executionType: executionType)
    }

    init(
        id: UUID = UUID(),
        session: WorkoutSession? = nil,
        timeSectionStep: TimeSectionStep? = nil,
        stepExerciseNameSnapshot: String? = nil,
        executionType: ExecutionType? = nil,
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
        self.executionType = executionType
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
