import Foundation
import SwiftData

/// Owns every session status/position transition. A workout can have at most one
/// `.paused` session at a time — starting a new one while a paused session exists
/// permanently supersedes it (it can never be finished afterward), per spec.
enum WorkoutSessionService {
    static func startNewSession(for workout: Workout, context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(workout: workout)
        positionAtStart(session, workout: workout)
        context.insert(session)

        if let paused = pausedSession(for: workout, context: context, excluding: session) {
            paused.freezeElapsedTime()
            paused.status = .abandonedUnfinished
            paused.endedAt = .now
            paused.supersededBySessionId = session.id
            paused.markDirty()
        }

        try? context.save()
        return session
    }

    static func pausedSession(for workout: Workout, context: ModelContext, excluding: WorkoutSession? = nil) -> WorkoutSession? {
        workout.sessions.first { $0.status == .paused && $0.id != excluding?.id }
    }

    static func pause(_ session: WorkoutSession, context: ModelContext) {
        session.freezeElapsedTime()
        session.status = .paused
        session.markDirty()
        try? context.save()
    }

    static func resume(_ session: WorkoutSession, context: ModelContext) {
        session.status = .inProgress
        session.resumeClock()
        session.markDirty()
        try? context.save()
    }

    static func abandon(_ session: WorkoutSession, context: ModelContext) {
        session.freezeElapsedTime()
        session.status = .abandonedUnfinished
        session.endedAt = .now
        session.markDirty()
        try? context.save()
    }

    static func finish(_ session: WorkoutSession, context: ModelContext) {
        session.freezeElapsedTime()
        session.status = .finished
        session.endedAt = .now
        session.markDirty()
        try? context.save()
    }

    static func positionAtStart(_ session: WorkoutSession, workout: Workout) {
        session.currentBlockIndex = 0
        setPositionForCurrentBlock(session, workout: workout)
    }

    static func setPositionForCurrentBlock(_ session: WorkoutSession, workout: Workout) {
        let blocks = workout.sortedBlocks
        guard session.currentBlockIndex < blocks.count else { return }
        let block = blocks[session.currentBlockIndex]
        if block.blockType == .time {
            session.currentStepIndex = 0
            session.currentExerciseIndex = nil
            session.currentSetIndex = nil
        } else {
            session.currentExerciseIndex = 0
            session.currentSetIndex = 0
            session.currentStepIndex = nil
        }
    }

    /// Advances to the next block, or finishes the session if the current one was last —
    /// this is how a mixed workout's blocks "stop when a new block starts."
    static func advanceBlock(_ session: WorkoutSession, workout: Workout, context: ModelContext) {
        session.currentBlockIndex += 1
        let blocks = workout.sortedBlocks
        if session.currentBlockIndex >= blocks.count {
            finish(session, context: context)
        } else {
            setPositionForCurrentBlock(session, workout: workout)
            session.markDirty()
            try? context.save()
        }
    }
}
