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
        session.currentSectionIndex = 0
        session.currentSectionRepeat = 0
        setPositionForCurrentSection(session, workout: workout)
    }

    static func setPositionForCurrentSection(_ session: WorkoutSession, workout: Workout) {
        let sections = workout.sortedSections
        guard session.currentSectionIndex < sections.count else { return }
        let section = sections[session.currentSectionIndex]
        switch section.sectionType {
        case .time:
            session.currentStepIndex = 0
            session.currentExerciseIndex = nil
            session.currentSetIndex = nil
        case .rep:
            session.currentExerciseIndex = 0
            session.currentSetIndex = 0
            session.currentStepIndex = nil
        case .emom:
            // currentStepIndex doubles as "current round" — same "position within the
            // section's ordered progression" role it plays for a time section.
            session.currentStepIndex = 0
            session.currentExerciseIndex = nil
            session.currentSetIndex = nil
        case .amrap:
            // currentSetIndex doubles as "rounds completed so far," incremented by
            // tapping the counter rather than by advancing through fixed items.
            session.currentSetIndex = 0
            session.currentStepIndex = nil
            session.currentExerciseIndex = nil
        }
    }

    /// Advances to the next section, or finishes the session if the current one was
    /// last — this is how a mixed workout's sections "stop when a new section starts."
    ///
    /// A section with `repeatCount > 1` runs again first: the repeat counter advances
    /// and the within-section position resets, leaving `currentSectionIndex` alone.
    static func advanceSection(_ session: WorkoutSession, workout: Workout, context: ModelContext) {
        let sections = workout.sortedSections

        if session.currentSectionIndex < sections.count {
            let section = sections[session.currentSectionIndex]
            let completedRepeat = session.currentSectionRepeat ?? 0
            if completedRepeat + 1 < section.effectiveRepeatCount {
                session.currentSectionRepeat = completedRepeat + 1
                setPositionForCurrentSection(session, workout: workout)
                session.markDirty()
                try? context.save()
                return
            }
        }

        session.currentSectionIndex += 1
        session.currentSectionRepeat = 0
        if session.currentSectionIndex >= sections.count {
            finish(session, context: context)
        } else {
            setPositionForCurrentSection(session, workout: workout)
            session.markDirty()
            try? context.save()
        }
    }
}
