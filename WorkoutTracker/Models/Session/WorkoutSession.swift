import Foundation
import SwiftData

enum SessionStatus: String, Codable {
    case inProgress, paused, finished, abandonedUnfinished
}

@Model
final class WorkoutSession: SyncableModel {
    @Attribute(.unique) var id: UUID
    var workout: Workout?
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date?

    /// Pause-safe elapsed time: `accumulatedActiveSeconds` is the frozen total as of the
    /// last pause/finish; `lastResumedAt` is non-nil only while `.inProgress`.
    var accumulatedActiveSeconds: Double
    var lastResumedAt: Date?

    /// Resumable position pointer. Safe as index-based because a workout referenced by
    /// any session is permanently locked, so its section/step ordering can never shift
    /// underneath a paused, later-resumed session.
    var currentSectionIndex: Int
    var currentStepIndex: Int?
    var currentExerciseIndex: Int?
    var currentSetIndex: Int?

    /// Set when a new session is started for the same workout while this one was still
    /// `.paused` — permanently disqualifies this session from ever being finished.
    var supersededBySessionId: UUID?

    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StepLog.session)
    var stepLogs: [StepLog] = []

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var setLogs: [SetLog] = []

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
        self.isDirty = true
        self.remoteSyncedAt = nil
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
