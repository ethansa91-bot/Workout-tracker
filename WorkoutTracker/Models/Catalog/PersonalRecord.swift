import Foundation
import SwiftData

/// A manually-set personal record for an exercise — independent of session
/// history. Never overwritten automatically by a later logged set; only changes
/// when the user explicitly edits and saves it. Reuses `RepExerciseTrackingMode`
/// (from the max-hold-time rep-block feature) so a record is either weight × reps
/// or a max hold time, matching the same two shapes a set can be logged as.
@Model
final class PersonalRecord: SyncableModel {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise?
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        weight: Double? = nil,
        reps: Int? = nil,
        holdSeconds: Int? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.trackingModeRaw = trackingMode.rawValue
        self.weight = weight
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }
}
