import Foundation
import SwiftData

enum SessionStatus: String, Codable {
    case inProgress, paused, finished, abandonedUnfinished
}

@Model
final class WorkoutSession: SyncableModel {
    var id: UUID = UUID()
    var workout: Workout?
    var statusRaw: String = SessionStatus.inProgress.rawValue
    var startedAt: Date = Date.now
    var endedAt: Date?

    /// Pause-safe elapsed time: `accumulatedActiveSeconds` is the frozen total as of the
    /// last pause/finish; `lastResumedAt` is non-nil only while `.inProgress`.
    var accumulatedActiveSeconds: Double = 0
    var lastResumedAt: Date?

    /// Resumable position pointer. Safe as index-based because a workout referenced by
    /// any session is permanently locked, so its section/step ordering can never shift
    /// underneath a paused, later-resumed session.
    var currentSectionIndex: Int = 0
    var currentStepIndex: Int?
    var currentExerciseIndex: Int?
    var currentSetIndex: Int?
    /// Which pass through the current section is running, 0-based. The four indices
    /// above are each already spoken for by a section type, so a repeated section
    /// needs its own counter. nil is treated as 0 (the first pass).
    var currentSectionRepeat: Int?

    /// Set when a new session is started for the same workout while this one was still
    /// `.paused` — permanently disqualifies this session from ever being finished.
    var supersededBySessionId: UUID?

    var updatedAt: Date = Date.now
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StepLog.session)
    var stepLogsStorage: [StepLog]?
    var stepLogs: [StepLog] {
        get { stepLogsStorage ?? [] }
        set { stepLogsStorage = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var setLogsStorage: [SetLog]?
    var setLogs: [SetLog] {
        get { setLogsStorage ?? [] }
        set { setLogsStorage = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSessionNote.session)
    var exerciseNotesStorage: [ExerciseSessionNote]?
    var exerciseNotes: [ExerciseSessionNote] {
        get { exerciseNotesStorage ?? [] }
        set { exerciseNotesStorage = newValue }
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), workout: Workout? = nil) {
        self.id = id
        self.workout = workout
        self.statusRaw = SessionStatus.inProgress.rawValue
        self.startedAt = .now
        self.endedAt = nil
        self.accumulatedActiveSeconds = 0
        self.lastResumedAt = .now
        self.currentSectionIndex = 0
        self.currentStepIndex = nil
        self.currentExerciseIndex = nil
        self.currentSetIndex = nil
        self.supersededBySessionId = nil
        self.updatedAt = .now
        self.deletedAt = nil
    }

    /// Live elapsed seconds, safe to read at any moment while running or paused.
    var elapsedSeconds: Double {
        guard status == .inProgress, let lastResumedAt else { return accumulatedActiveSeconds }
        return accumulatedActiveSeconds + Date.now.timeIntervalSince(lastResumedAt)
    }

    /// Folds the live delta into the frozen total and stops the running clock. Call
    /// before transitioning to `.paused`, `.finished`, or `.abandonedUnfinished`.
    func freezeElapsedTime() {
        if status == .inProgress, let lastResumedAt {
            accumulatedActiveSeconds += Date.now.timeIntervalSince(lastResumedAt)
        }
        lastResumedAt = nil
    }

    /// Call when transitioning back to `.inProgress` from `.paused`.
    func resumeClock() {
        lastResumedAt = .now
    }
}
