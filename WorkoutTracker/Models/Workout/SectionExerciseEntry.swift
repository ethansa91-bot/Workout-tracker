import Foundation
import SwiftData

/// One exercise in an EMOM or AMRAP section. Unlike `RepSectionExercise`, there are no
/// per-exercise settings (sets/rest/tracking mode) — every exercise in the section is
/// shown at once and the whole section shares a single timer.
///
/// The one exception is `executionType`: how an exercise is performed is a property of the
/// exercise, not of the timing around it, so an EMOM burpee can be explosive for the same
/// reason a rep-section one can.
@Model
final class SectionExerciseEntry: SyncableModel, Orderable {
    var id: UUID = UUID()
    var section: WorkoutSection?
    var sortOrder: Int = 0
    var exercise: Exercise?
    /// How this section performs the exercise. Fixed for the run — EMOM and AMRAP show
    /// every exercise at once with no per-exercise controls, so there is nowhere to change
    /// it mid-workout the way a rep entry can.
    var executionType: ExecutionType?
    /// How many reps this section prescribes. **0 means unset**, and reads as no rep count
    /// at all — which is what every EMOM and AMRAP entry written before this existed has,
    /// so those workouts keep showing bare exercise names.
    ///
    /// Non-optional with a default because CloudKit mirroring requires it, the same reason
    /// `RepSectionExercise.targetSets` is an `Int` rather than an `Int?`.
    var targetReps: Int = 0
    /// Raw value of `side`. nil for an entry worked both sides — including every entry
    /// written before one-sided entries existed. Only meaningful when the exercise is
    /// marked `isOneSided`.
    var sideRaw: String?
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    /// The publisher's `ArchiveQuickExercise.id`, for the same reason `WorkoutSection`
    /// carries `sourceSectionId` one level up — see that field's doc comment.
    var sourceEntryId: UUID?

    init(id: UUID = UUID(), section: WorkoutSection? = nil, sortOrder: Int, exercise: Exercise? = nil, executionType: ExecutionType? = nil, targetReps: Int = 0) {
        self.id = id
        self.section = section
        self.sortOrder = sortOrder
        self.exercise = exercise
        self.executionType = executionType
        self.targetReps = targetReps
        self.updatedAt = .now
        self.deletedAt = nil
    }

    /// Which side this entry works, when the exercise is one-sided. Same meaning as
    /// `TimeSectionStep.side`, and for the same reason: an EMOM has no per-exercise
    /// controls during the run, so the choice belongs to the plan.
    var side: SetSide? {
        get { sideRaw.flatMap(SetSide.init(rawValue:)) }
        set { sideRaw = newValue?.rawValue }
    }

    /// What this row is called wherever it's listed — "12 × Push Up, Explosive".
    ///
    /// The rep count goes in the *title* rather than in a detail line because the two grid
    /// runners are where it matters most, and their cells have no detail line to put it on.
    /// Composed on top of `ExerciseNaming` rather than inside it: that helper is shared
    /// with rep entries, time steps and both log types, none of which have a rep target.
    var displayTitle: String {
        let name = ExerciseNaming.title(exercise, side: side, executionType: executionType)
        guard targetReps > 0 else { return name }
        return "\(targetReps) × \(name)"
    }
}
