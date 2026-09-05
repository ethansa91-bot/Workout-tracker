import Foundation
import SwiftData

/// Historical-performance lookups that power both the rep-session set-row prefill and
/// the "you're doing worse than last time" comparison.
enum SetLogQueries {
    /// Every lookup here takes an optional `executionType` paired with an explicit
    /// `scopesByExecutionType` flag rather than reading nil as "all types".
    ///
    /// nil already means two different things across this file — "any equipment" in
    /// `bestSetEver`, "unloaded only" in `bestHoldEver` — and a third reading of it would
    /// make every call site guess. With the flag off, behaviour is exactly what it was
    /// before execution types existed; with it on, nil means the untyped slice specifically.
    struct BestSet {
        let weight: Double
        let reps: Int
    }

    /// The best set (highest weight, ties broken by most reps in that set) from the
    /// most recent *prior* session that logged this exercise. Used both to prefill a
    /// new set's reps/weight and as the comparison baseline shown alongside it.
    ///
    /// Hold sets are excluded (`holdSeconds == nil`): they store `reps`/`weight` as `0`
    /// sentinels, so an exercise last trained as a max hold in some other workout would
    /// otherwise report a "last set" of 0 × 0 and wipe out a real weight history.
    /// Bodyweight sets are excluded for the same reason — their `weight` is `0` because
    /// nothing was loaded, not because 0 was the load lifted.
    /// `equipment` scopes the lookup to sets logged on that equipment — history from a
    /// barbell shouldn't prefill a dumbbell set. Pass `nil` for all equipment.
    static func lastBestSet(exercise: Exercise, equipment: Equipment? = nil, executionType: ExecutionType? = nil, scopesByExecutionType: Bool = false, excluding session: WorkoutSession, context: ModelContext) -> BestSet? {
        let exerciseID = exercise.id
        let sessionID = session.id
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in
                log.exercise?.id == exerciseID && log.isCancelled == false && log.session?.id != sessionID && log.holdSeconds == nil && log.isBodyweight == nil
            },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard var logs = try? context.fetch(descriptor), !logs.isEmpty else { return nil }
        if let equipment {
            logs = logs.filter { $0.equipment?.id == equipment.id }
        }
        logs = scoped(logs, to: executionType, enabled: scopesByExecutionType)
        guard !logs.isEmpty else { return nil }
        guard let mostRecentSessionID = logs.first?.session?.id else { return nil }
        let mostRecentSessionLogs = logs.filter { $0.session?.id == mostRecentSessionID }
        guard let best = mostRecentSessionLogs.max(by: { a, b in
            if a.weight != b.weight { return a.weight < b.weight }
            return a.reps < b.reps
        }) else { return nil }
        return BestSet(weight: best.weight, reps: best.reps)
    }

    /// Narrows a fetched batch to one execution type, or leaves it untouched when the
    /// caller isn't splitting. Kept as one helper so every lookup applies the rule the
    /// same way — nil with the flag on means "logged without a type", not "any type".
    private static func scoped(_ logs: [SetLog], to executionType: ExecutionType?, enabled: Bool) -> [SetLog] {
        guard enabled else { return logs }
        let id = executionType?.id
        return logs.filter { $0.executionType?.id == id }
    }

    // MARK: - Bodyweight
    //
    // Separate from the weighted lookups rather than relaxing their `isBodyweight ==
    // nil` filters: a bodyweight set logs no load, so letting one through as a
    // "best set" would surface a meaningless 0 kg hint mid-workout. Equipment is
    // ignored here — bodyweight is the load, whatever bar it was done on.

    /// Most reps at body load in the most recent session that has any, excluding the
    /// one in progress.
    static func lastBodyweightReps(exercise: Exercise, executionType: ExecutionType? = nil, scopesByExecutionType: Bool = false, excluding session: WorkoutSession, context: ModelContext) -> Int? {
        let exerciseID = exercise.id
        let sessionID = session.id
        // The bodyweight/hold conditions are applied in Swift rather than in the
        // predicate — folding all five into one `#Predicate` pushes the type-checker
        // past its limit and fails to compile.
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in
                log.exercise?.id == exerciseID && log.isCancelled == false && log.session?.id != sessionID
            },
            sortBy: [SortDescriptor(\SetLog.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        guard let fetched = try? context.fetch(descriptor) else { return nil }
        let logs = scoped(fetched.filter { $0.holdSeconds == nil && $0.isBodyweight == true },
                          to: executionType, enabled: scopesByExecutionType)
        guard !logs.isEmpty, let mostRecentSessionID = logs.first?.session?.id else { return nil }
        return logs.filter { $0.session?.id == mostRecentSessionID }.map(\.reps).max()
    }

    /// Most reps at body load across all history.
    static func bestBodyweightRepsEver(exercise: Exercise, executionType: ExecutionType? = nil, scopesByExecutionType: Bool = false, context: ModelContext) -> Int? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in
                log.exercise?.id == exerciseID && log.isCancelled == false
            }
        )
        guard let fetched = try? context.fetch(descriptor) else { return nil }
        return scoped(fetched.filter { $0.holdSeconds == nil && $0.isBodyweight == true },
                      to: executionType, enabled: scopesByExecutionType)
            .map(\.reps)
            .max()
    }

    /// The best set (highest weight, ties broken by most reps) across *all* history,
    /// not scoped to the most recent session — used for an all-time personal record,
    /// where `lastBestSet`'s "most recent session only" scoping would be wrong.
    static func bestSetEver(exercise: Exercise, equipment: Equipment? = nil, executionType: ExecutionType? = nil, scopesByExecutionType: Bool = false, context: ModelContext) -> BestSet? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false && log.holdSeconds == nil && log.isBodyweight == nil }
        )
        guard var logs = try? context.fetch(descriptor), !logs.isEmpty else { return nil }
        if let equipment {
            logs = logs.filter { $0.equipment?.id == equipment.id }
        }
        logs = scoped(logs, to: executionType, enabled: scopesByExecutionType)
        guard !logs.isEmpty else { return nil }
        guard let best = logs.max(by: { a, b in
            if a.weight != b.weight { return a.weight < b.weight }
            return a.reps < b.reps
        }) else { return nil }
        return BestSet(weight: best.weight, reps: best.reps)
    }

    /// Hold sets excluded for the same reason as `lastBestSet` — their `weight` is a
    /// `0` sentinel, not a real load.
    static func maxWeightEver(exercise: Exercise, context: ModelContext) -> Double? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false && log.holdSeconds == nil }
        )
        guard let logs = try? context.fetch(descriptor) else { return nil }
        return logs.map(\.weight).max()
    }

    /// The longest hold ever recorded for this exercise, across all sessions.
    ///
    /// Scoped by equipment the same way `bestSetEver` is: a hold can be loaded, and a
    /// 90s unweighted plank isn't the same achievement as a 90s plank under a 20 lb
    /// plate. `nil` equipment means unloaded holds only.
    static func bestHoldEver(exercise: Exercise, equipment: Equipment? = nil, executionType: ExecutionType? = nil, scopesByExecutionType: Bool = false, context: ModelContext) -> Int? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in log.exercise?.id == exerciseID && log.isCancelled == false && log.holdSeconds != nil }
        )
        guard let logs = try? context.fetch(descriptor) else { return nil }
        return scoped(logs.filter { $0.equipment?.id == equipment?.id },
                      to: executionType, enabled: scopesByExecutionType)
            .compactMap(\.holdSeconds)
            .max()
    }

    /// The best hold from the most recent *prior* session that logged this exercise —
    /// same "most recent session, best value within it" shape as `lastBestSet`.
    static func lastHoldSeconds(exercise: Exercise, equipment: Equipment? = nil, executionType: ExecutionType? = nil, scopesByExecutionType: Bool = false, excluding session: WorkoutSession, context: ModelContext) -> Int? {
        let exerciseID = exercise.id
        let sessionID = session.id
        var descriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { log in
                log.exercise?.id == exerciseID && log.isCancelled == false && log.session?.id != sessionID && log.holdSeconds != nil
            },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        guard let fetched = try? context.fetch(descriptor) else { return nil }
        let logs = scoped(fetched.filter { $0.equipment?.id == equipment?.id },
                          to: executionType, enabled: scopesByExecutionType)
        guard !logs.isEmpty else { return nil }
        guard let mostRecentSessionID = logs.first?.session?.id else { return nil }
        let mostRecentSessionLogs = logs.filter { $0.session?.id == mostRecentSessionID }
        return mostRecentSessionLogs.compactMap(\.holdSeconds).max()
    }
}
