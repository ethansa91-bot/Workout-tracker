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
    var isBodyweight: Bool = false
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    var weightUnit: String?
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
        isBodyweight: Bool = false,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        weight: Double? = nil,
        reps: Int? = nil,
        holdSeconds: Int? = nil,
        weightUnit: String? = nil,
        achievedAt: Date = .now
    ) {
        self.id = id
        self.record = record
        self.exercise = exercise
        self.equipment = equipment
        self.isBodyweight = isBodyweight
        self.trackingModeRaw = trackingMode.rawValue
        self.weight = weight
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.weightUnit = weightUnit
        self.achievedAt = achievedAt
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }
}
