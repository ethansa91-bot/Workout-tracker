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

    static func maxWeightEver(exercise: Exercise, context: ModelContext) -> Double? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false }
        )
        guard let logs = try? context.fetch(descriptor) else { return nil }
        return logs.map(\.weight).max()
    }
}
