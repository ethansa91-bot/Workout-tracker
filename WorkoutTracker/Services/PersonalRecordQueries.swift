import Foundation
import SwiftData

enum PersonalRecordQueries {
    /// The manually-saved record for this exercise, if any — takes precedence over
    /// derived session-history bests wherever both are consulted.
    static func current(for exercise: Exercise, context: ModelContext) -> PersonalRecord? {
        let exerciseID = exercise.id
        var descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
