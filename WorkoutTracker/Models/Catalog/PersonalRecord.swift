import Foundation
import SwiftData

/// A manually-set personal record for an exercise — independent of session
/// history. Never overwritten automatically by a later logged set; only changes
/// when the user explicitly edits and saves it. Reuses `RepExerciseTrackingMode`
/// (from the max-hold-time rep-section feature) so a record is either weight × reps
/// or a max hold time, matching the same two shapes a set can be logged as.
@Model
final class PersonalRecord: SyncableModel {
    var id: UUID = UUID()
    var exercise: Exercise?
    /// Which equipment the record was set on. Records are kept per equipment — a
    /// barbell best and a dumbbell best aren't the same lift, and the same goes for a
    /// loaded hold vs. an unloaded one. nil for records made before this existed, and
    /// for holds performed with no load.
    var equipment: Equipment?
    /// The unit the record's `weight` is expressed in. Previously re-derived at display
    /// time from the exercise's current equipment, which silently reinterpreted the
    /// number whenever that resolution changed.
    var weightUnit: String?
    /// A bodyweight record is the exercise done at body load — best measured in reps,
    /// with no weight and no equipment, so it never merges with a weighted record for
    /// the same exercise. Non-optional with a `false` default so records written before
    /// this existed decode correctly: every one of them was weighted or a hold.
    var isBodyweight: Bool = false
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// Superseded values, newest first via `history`. Cascades: a deleted record's past
    /// has nothing left to belong to. Optional at the type level because CloudKit
    /// requires it of every to-many relationship.
    @Relationship(deleteRule: .cascade, inverse: \PersonalRecordEntry.record)
    var historyStorage: [PersonalRecordEntry]?
    var history: [PersonalRecordEntry] {
        get { (historyStorage ?? []).filter { $0.deletedAt == nil }.sorted { $0.achievedAt > $1.achievedAt } }
        set { historyStorage = newValue }
    }

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        equipment: Equipment? = nil,
        weightUnit: String? = nil,
        isBodyweight: Bool = false,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        weight: Double? = nil,
        reps: Int? = nil,
        holdSeconds: Int? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.equipment = equipment
        self.weightUnit = weightUnit
        self.isBodyweight = isBodyweight
        self.trackingModeRaw = trackingMode.rawValue
        self.weight = weight
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }
}
