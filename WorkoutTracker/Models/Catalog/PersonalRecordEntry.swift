import Foundation
import SwiftData

/// One superseded value of a `PersonalRecord`, kept so a record reads as a timeline
/// rather than a single number that silently overwrites itself.
///
/// Written only when a record is replaced — by an explicit edit, or by a set logged
/// mid-workout that beats the standing value. The entry carries the *old* values and the
/// date they were achieved, so the record itself always holds the current best.
///
/// `exercise` and `equipment` are denormalised rather than read through `record`: history
/// is the thing worth keeping if a record row is ever removed, and querying by exercise
/// directly avoids walking every record to find one exercise's past.
@Model
final class PersonalRecordEntry: SyncableModel {
    var id: UUID = UUID()
    var record: PersonalRecord?
    var exercise: Exercise?
    var equipment: Equipment?
    /// Denormalised from the record for the same reason `exercise` and `equipment` are:
    /// history outlives the record row it superseded.
    var executionType: ExecutionType?
    var isBodyweight: Bool = false
    /// Denormalised from the record, like every other facet here: history outlives the
    /// record row it superseded, and a Follow Along value read as a hold would be wrong.
    var isFollowAlong: Bool = false
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    var weightUnit: String?
    /// Denormalised from the record for the same reason every other facet here is:
    /// history outlives the record row it superseded, and a section round count read as
    /// a rep count would be wrong. See `PersonalRecord.sectionRecordGroupID`.
    var sectionRecordGroupID: UUID?
    var sectionRecordKindRaw: String?
    var sectionRecordName: String?
    /// When this value was achieved — the whole point of the model. `updatedAt` is the
    /// sync clock and moves whenever the row is touched, so it can't stand in for this.
    var achievedAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        record: PersonalRecord? = nil,
        exercise: Exercise? = nil,
        equipment: Equipment? = nil,
        executionType: ExecutionType? = nil,
        isBodyweight: Bool = false,
        isFollowAlong: Bool = false,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        weight: Double? = nil,
        reps: Int? = nil,
        holdSeconds: Int? = nil,
        weightUnit: String? = nil,
        sectionRecordGroupID: UUID? = nil,
        sectionRecordKind: WorkoutSectionType? = nil,
        sectionRecordName: String? = nil,
        achievedAt: Date = .now
    ) {
        self.id = id
        self.record = record
        self.exercise = exercise
        self.equipment = equipment
        self.executionType = executionType
        self.isBodyweight = isBodyweight
        self.isFollowAlong = isFollowAlong
        self.trackingModeRaw = trackingMode.rawValue
        self.weight = weight
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.weightUnit = weightUnit
        self.sectionRecordGroupID = sectionRecordGroupID
        self.sectionRecordKindRaw = sectionRecordKind?.rawValue
        self.sectionRecordName = sectionRecordName
        self.achievedAt = achievedAt
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }

    var isSectionRecord: Bool { sectionRecordGroupID != nil }

    var sectionRecordKind: WorkoutSectionType? {
        get { sectionRecordKindRaw.flatMap(WorkoutSectionType.init(rawValue:)) }
        set { sectionRecordKindRaw = newValue?.rawValue }
    }
}
