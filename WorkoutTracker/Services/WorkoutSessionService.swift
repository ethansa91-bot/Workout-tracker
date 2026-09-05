import Foundation
import SwiftData

/// Owns every session status/position transition. A workout can have at most one
/// `.paused` session at a time — starting a new one while a paused session exists
/// permanently supersedes it (it can never be finished afterward), per spec.
/// What comes after the section a session is currently on.
enum SectionLookahead {
    /// The same section runs again — the pass counter moves, the section index doesn't.
    case anotherPass(WorkoutSection)
    case nextSection(WorkoutSection)
    case endOfWorkout
}

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

    /// Discards a session outright. `stepLogsStorage`, `setLogsStorage` and
    /// `exerciseNotesStorage` are all `.cascade`, so everything logged in it goes too;
    /// `Workout.sessionsStorage` is `.nullify`, so the workout itself survives and
    /// simply stops counting this session toward `isLocked`.
    static func delete(_ session: WorkoutSession, context: ModelContext) {
        context.delete(session)
        try? context.save()
    }

    /// Whether a section's `.time`/`.emom`/`.amrap` runner should start counting down the
    /// instant it appears, rather than waiting for a tap.
    ///
    /// `autostart` only answers for the section's very first pass — a repeat is a
    /// continuation of something already actively running, not a new stopping point that
    /// asks again. `SessionRunnerView` rebuilds the runner view fresh on every pass (so
    /// each round's own local state resets), and that rebuild re-runs the runner's
    /// `init`; without checking the pass here, an autostart-off section would silently
    /// re-pause itself before every single repeat instead of only its first.
    static func autostartsRunning(_ session: WorkoutSession, section: WorkoutSection) -> Bool {
        (session.currentSectionRepeat ?? 0) > 0 || section.autostart
    }

    static func finish(_ session: WorkoutSession, context: ModelContext) {
        session.freezeElapsedTime()
        session.status = .finished
        session.endedAt = .now
        session.markDirty()
        try? context.save()
        // Deliberately doesn't file an EMOM/AMRAP result as a record here — this is the
        // moment the session ends, not the moment the user is done looking at it. Filing
        // here would commit a number the summary screen hasn't shown them yet, with no
        // chance to correct a stray tap on the round counter before it became a personal
        // record. `SessionSummaryView` commits it instead, once the review it offers is
        // actually dismissed — see `SectionResultService.commitCorrectedResult`.
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
        switch lookahead(session, workout: workout) {
        case .anotherPass:
            session.currentSectionRepeat = (session.currentSectionRepeat ?? 0) + 1
            setPositionForCurrentSection(session, workout: workout)
            session.markDirty()
            try? context.save()
        case .nextSection:
            session.currentSectionIndex += 1
            session.currentSectionRepeat = 0
            setPositionForCurrentSection(session, workout: workout)
            session.markDirty()
            try? context.save()
        case .endOfWorkout:
            session.currentSectionIndex += 1
            session.currentSectionRepeat = 0
            finish(session, context: context)
        }
    }

    /// What follows the section the session is on, without moving to it.
    ///
    /// Extracted so the runner can say what is coming *before* it gets there — the voice
    /// names the next exercise a few seconds before a section ends — and `advanceSection`
    /// switches on the same answer, so the two can't come to different conclusions about
    /// whether a pass or a section is next.
    static func lookahead(_ session: WorkoutSession, workout: Workout) -> SectionLookahead {
        let sections = workout.sortedSections

        if session.currentSectionIndex < sections.count {
            let section = sections[session.currentSectionIndex]
            let completedRepeat = session.currentSectionRepeat ?? 0
            if completedRepeat + 1 < section.effectiveRepeatCount {
                return .anotherPass(section)
            }
        }

        let nextIndex = session.currentSectionIndex + 1
        guard nextIndex < sections.count else { return .endOfWorkout }
        return .nextSection(sections[nextIndex])
    }
}
