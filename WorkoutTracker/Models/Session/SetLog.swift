import Foundation
import SwiftData

/// One logged set in a rep block. "Stop sets" isn't a stored flag — an exercise
/// advanced past with fewer than `targetSets` non-cancelled logs was stopped early.
@Model
final class SetLog: SyncableModel {
    @Attribute(.unique) var id: UUID
    var session: WorkoutSession?
    var repBlockExercise: RepBlockExercise?
    /// Denormalized alongside `repBlockExercise` so "last best set" / "max weight ever"
    /// queries can filter directly on `exercise.id` without joining through the block.
    var exercise: Exercise?
    var exerciseNameSnapshot: String?
    var setIndex: Int
    var reps: Int
    var weight: Double
    /// Snapshot of the app-wide unit at logging time, so a later unit-setting change
    /// doesn't retroactively misrepresent history.
    var weightUnit: String
    /// Non-nil means this is a max-hold-time set — `reps`/`weight` are unused
    /// sentinel values (`0`) for it. This alone is the mode discriminator, no
    /// separate flag needed.
    var holdSeconds: Int?
    var loggedAt: Date
    /// Edit/cancel support: a cancelled set is excluded from progress counts and from
    /// best/max computations; logging again fills the slot.
    var isCancelled: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    init(
        id: UUID = UUID(),
        session: WorkoutSession? = nil,
        repBlockExercise: RepBlockExercise? = nil,
        exercise: Exercise? = nil,
        exerciseNameSnapshot: String? = nil,
        setIndex: Int,
        reps: Int,
        weight: Double,
        weightUnit: String,
        holdSeconds: Int? = nil,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.session = session
        self.repBlockExercise = repBlockExercise
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.holdSeconds = holdSeconds
        self.loggedAt = .now
        self.isCancelled = isCancelled
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
