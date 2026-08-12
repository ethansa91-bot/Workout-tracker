import Foundation
import SwiftData

/// Historical-performance lookups that power both the rep-session set-row prefill and
/// the "you're doing worse than last time" comparison.
enum SetLogQueries {
    struct BestSet {
        let weight: Double
        let reps: Int
    }

    /// The best set (highest weight, ties broken by most reps in that set) from the
    /// most recent *prior* session that logged this exercise. Used both to prefill a
    /// new set's reps/weight and as the comparison baseline shown alongside it.
    static func lastBestSet(exercise: Exercise, excluding session: WorkoutSession, context: ModelContext) -> BestSet? {
        let exerciseID = exercise.id
        let sessionID = session.id
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in
                log.exercise?.id == exerciseID && log.isCancelled == false && log.session?.id != sessionID
            },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard let logs = try? context.fetch(descriptor), !logs.isEmpty else { return nil }
        guard let mostRecentSessionID = logs.first?.session?.id else { return nil }
        let mostRecentSessionLogs = logs.filter { $0.session?.id == mostRecentSessionID }
        guard let best = mostRecentSessionLogs.max(by: { a, b in
            if a.weight != b.weight { return a.weight < b.weight }
            return a.reps < b.reps
        }) else { return nil }
        return BestSet(weight: best.weight, reps: best.reps)
    }

    /// The best set (highest weight, ties broken by most reps) across *all* history,
    /// not scoped to the most recent session — used for an all-time personal record,
    /// where `lastBestSet`'s "most recent session only" scoping would be wrong.
    static func bestSetEver(exercise: Exercise, context: ModelContext) -> BestSet? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false && log.holdSeconds == nil }
        )
        guard let logs = try? context.fetch(descriptor), !logs.isEmpty else { return nil }
        guard let best = logs.max(by: { a, b in
            if a.weight != b.weight { return a.weight < b.weight }
            return a.reps < b.reps
        }) else { return nil }
        return BestSet(weight: best.weight, reps: best.reps)
    }

    static func maxWeightEver(exercise: Exercise, context: ModelContext) -> Double? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false }
        )
        guard let logs = try? context.fetch(descriptor) else { return nil }
        return logs.map(\.weight).max()
    }

    /// The longest hold ever recorded for this exercise, across all sessions.
    static func bestHoldEver(exercise: Exercise, context: ModelContext) -> Int? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false && log.holdSeconds != nil }
        )
        guard let logs = try? context.fetch(descriptor) else { return nil }
        return logs.compactMap(\.holdSeconds).max()
    }

    /// The best hold from the most recent *prior* session that logged this exercise —
    /// same "most recent session, best value within it" shape as `lastBestSet`.
    static func lastHoldSeconds(exercise: Exercise, excluding session: WorkoutSession, context: ModelContext) -> Int? {
        let exerciseID = exercise.id
        let sessionID = session.id
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in
                log.exercise?.id == exerciseID && log.isCancelled == false && log.session?.id != sessionID && log.holdSeconds != nil
            },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard let logs = try? context.fetch(descriptor), !logs.isEmpty else { return nil }
        guard let mostRecentSessionID = logs.first?.session?.id else { return nil }
        let mostRecentSessionLogs = logs.filter { $0.session?.id == mostRecentSessionID }
        return mostRecentSessionLogs.compactMap(\.holdSeconds).max()
    }
}
