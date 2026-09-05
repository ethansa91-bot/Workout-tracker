import Foundation
import SwiftData

/// How an exercise is performed — explosive, slow, held, and whatever else the user adds.
///
/// A sibling of `Equipment` rather than an enum: the vocabulary is open, since what counts
/// as a distinct way of performing a lift is the user's call, and new ones are created
/// inline from the exercise page. Every type is available to every exercise; attaching one
/// is what makes it offerable there.
///
/// Deliberately carries no icon and no flags. `Equipment` needs `isWeighted` because it
/// changes what a set *records*; an execution type only changes what a set is *called* and
/// — when the exercise opts in via `Exercise.separateRecordsPerExecutionType` — which
/// record it files under.
@Model
final class ExecutionType: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    /// True for types the user created themselves, vs. the seeded defaults.
    var isCustom: Bool = false
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The many-to-many inverse of `Exercise.executionTypesStorage`. The
    /// `@Relationship(inverse:)` annotation itself lives on the `Exercise` side — this is
    /// the plain matching property, exactly as `Equipment.exercisesStorage` is.
    var exercisesStorage: [Exercise]?
    var exercises: [Exercise] {
        get { exercisesStorage ?? [] }
        set { exercisesStorage = newValue }
    }

    /// Back-references that exist only to satisfy CloudKit's "every relationship needs an
    /// inverse" rule for the one-directional lookups on the other models — nothing in the
    /// app reads or writes them.
    @Relationship(inverse: \RepSectionExercise.executionType)
    var repSectionExercises: [RepSectionExercise]?

    @Relationship(inverse: \TimeSectionStep.executionType)
    var timeSectionSteps: [TimeSectionStep]?

    @Relationship(inverse: \SectionExerciseEntry.executionType)
    var sectionExerciseEntries: [SectionExerciseEntry]?

    @Relationship(inverse: \SetLog.executionType)
    var setLogs: [SetLog]?

    @Relationship(inverse: \StepLog.executionType)
    var stepLogs: [StepLog]?

    @Relationship(inverse: \PersonalRecord.executionType)
    var personalRecords: [PersonalRecord]?

    @Relationship(inverse: \PersonalRecordEntry.executionType)
    var personalRecordEntries: [PersonalRecordEntry]?

    init(id: UUID = UUID(), name: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.isCustom = isCustom
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
