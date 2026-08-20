import Foundation
import SwiftData

/// Which side of the body a set was performed on, for exercises tracked one side at a
/// time. Absent on ordinary sets.
enum SetSide: String, Codable, CaseIterable {
    case left, right

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var shortLabel: String {
        switch self {
        case .left: return "L"
        case .right: return "R"
        }
    }
}

/// One logged set in a rep section. "Stop sets" isn't a stored flag — an exercise
/// advanced past with fewer than `targetSets` non-cancelled logs was stopped early.
@Model
final class SetLog: SyncableModel {
    var id: UUID = UUID()
    var session: WorkoutSession?
    var repSectionExercise: RepSectionExercise?
    /// Denormalized alongside `repSectionExercise` so "last best set" / "max weight ever"
    /// queries can filter directly on `exercise.id` without joining through the section.
    var exercise: Exercise?
    var exerciseNameSnapshot: String?
    var setIndex: Int = 0
    var reps: Int = 0
    var weight: Double = 0
    /// Snapshot of the app-wide unit at logging time, so a later unit-setting change
    /// doesn't retroactively misrepresent history.
    var weightUnit: String = "lb"
    /// Non-nil means this is a max-hold-time set — `reps`/`weight` are unused
    /// sentinel values (`0`) for it. This alone is the mode discriminator, no
    /// separate flag needed.
    var holdSeconds: Int?
    /// `true` when the set was performed unloaded. `weight` is `0` either way, so this
    /// is what tells "bodyweight" apart from "0 lb". nil = an ordinary loaded set.
    var isBodyweight: Bool?
    /// Raw value of `side`. nil for a normal both-sides set — including every set
    /// logged before one-sided tracking existed.
    var sideRaw: String?
    /// Which pass through a repeated section this set belongs to, 0-based. `setIndex`
    /// identifies the slot within one pass, so without this a section run three times
    /// would see every slot filled after the first pass and refuse further sets.
    var repeatIndex: Int = 0
    /// Which weighted equipment the set was performed on. `weightUnit` alone can't
    /// identify it — several equipment share the same unit — and records are kept per
    /// equipment, so the reference has to be stored.
    var equipment: Equipment?
    /// `true` when the weight was typed in rather than picked from an equipment's
    /// preset combos. nil = an ordinary equipment-backed set.
    var isManualWeight: Bool?
    var loggedAt: Date = Date.now
    /// Edit/cancel support: a cancelled set is excluded from progress counts and from
    /// best/max computations; logging again fills the slot.
    var isCancelled: Bool = false
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        session: WorkoutSession? = nil,
        repSectionExercise: RepSectionExercise? = nil,
        exercise: Exercise? = nil,
        exerciseNameSnapshot: String? = nil,
        setIndex: Int,
        reps: Int,
        weight: Double,
        weightUnit: String,
        holdSeconds: Int? = nil,
        isBodyweight: Bool? = nil,
        side: SetSide? = nil,
        repeatIndex: Int = 0,
        equipment: Equipment? = nil,
        isManualWeight: Bool? = nil,
        isCancelled: Bool = false
    ) {
        self.id = id
        self.session = session
        self.repSectionExercise = repSectionExercise
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.holdSeconds = holdSeconds
        self.isBodyweight = isBodyweight
        self.sideRaw = side?.rawValue
        self.repeatIndex = repeatIndex
        self.equipment = equipment
        self.isManualWeight = isManualWeight
        self.loggedAt = .now
        self.isCancelled = isCancelled
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var side: SetSide? {
        get { sideRaw.flatMap(SetSide.init(rawValue:)) }
        set { sideRaw = newValue?.rawValue }
    }
}
