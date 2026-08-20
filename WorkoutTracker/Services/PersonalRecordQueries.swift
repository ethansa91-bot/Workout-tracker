import Foundation
import SwiftData

enum PersonalRecordQueries {
    /// The manually-saved record for this exercise, if any — takes precedence over
    /// derived session-history bests wherever both are consulted.
    /// Any record for the exercise, ignoring equipment — used where a single headline
    /// number is wanted (the hold-time best, the in-session seed).
    static func current(for exercise: Exercise, context: ModelContext) -> PersonalRecord? {
        let exerciseID = exercise.id
        var descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The record for one exercise on one specific equipment. Records are kept per
    /// equipment, so this is the lookup that matches how they're saved; `nil`
    /// equipment means a record with no equipment attached.
    static func current(for exercise: Exercise, equipment: Equipment?, context: ModelContext) -> PersonalRecord? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.deletedAt == nil }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.first { $0.equipment?.id == equipment?.id }
    }
}
