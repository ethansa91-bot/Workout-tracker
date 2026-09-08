import Foundation
import SwiftData
import SwiftUI

enum TimeStepType: String, Codable {
    case exercise, rest, getReady
}

/// A single step's user-assigned color — every exercise in a follow-along section can
/// have its own, so `SessionScrubStripView` highlights each chip in its own color
/// while it's the active step, instead of one fixed accent color for the whole strip.
enum PaletteColor: String, Codable, CaseIterable, Identifiable {
    case green, blue, brown, orange, yellow, purple, red, gray

    var id: String { rawValue }

    /// Deep/muted tones matching `appAccent`'s tonal family, not bright system colors —
    /// so a colored step reads as part of the app's palette rather than clashing with it.
    var color: Color {
        switch self {
        case .green: return .appAccent
        case .blue: return .appStepBlue
        case .brown: return .appStepBrown
        case .orange: return .appRust
        case .yellow: return .appStepYellow
        case .purple: return .appStepPurple
        case .red: return .appDanger
        case .gray: return .appInkMuted
        }
    }

    var label: String { rawValue.capitalized }
}

/// One entry in a time section's sequence: either an exercise held for a duration, or a
/// rest. From a UI/runtime perspective a rest behaves exactly like an exercise step
/// (it has a duration and advances the same way) except it has no picture.
@Model
final class TimeSectionStep: SyncableModel, Orderable {
    var id: UUID = UUID()
    var section: WorkoutSection?
    var sortOrder: Int = 0
    var stepTypeRaw: String = TimeStepType.exercise.rawValue
    /// nil for rest steps.
    var exercise: Exercise?
    var durationSeconds: Int = 0
    /// Backing storage for `color` — `nil` means "no custom color," which falls back
    /// to the app's default accent in the scrub strip.
    var colorRaw: String?
    /// How this step's exercise is performed. Fixed for the whole run — a Follow Along
    /// step is chosen when the workout is built and can't be changed mid-workout, unlike
    /// a rep entry's. nil for rest steps and for any step that names no type.
    var executionType: ExecutionType?
    /// Raw value of `side`. nil for a step worked both sides — including every step
    /// written before one-sided steps existed. Only meaningful when the exercise is
    /// marked `isOneSided`.
    var sideRaw: String?
    /// Which weighted equipment this workout holds the step with, when the exercise has
    /// more than one. nil falls back to the exercise's own resolution. Mirrors
    /// `RepSectionExercise.preferredEquipment` — a loaded plank is a loaded plank whether
    /// it is counted in sets or held for a duration.
    var preferredEquipment: Equipment?
    /// This step is performed unloaded, ignoring `preferredEquipment`. Non-optional with a
    /// `false` default so steps written before this existed decode correctly.
    var prefersBodyweight: Bool = false
    /// The weight this step's post-session record card
    /// (`FollowAlongRecordCard.prefill`) prefills at when there's no personal record yet
    /// for the exercise on this equipment — the Follow Along counterpart to
    /// `RepSectionExercise.startingWeight`. No reps counterpart: a held step has none to
    /// seed. nil falls back to the equipment's lightest preset, exactly as before this
    /// existed.
    var startingWeight: Double?
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    /// The publisher's `ArchiveTimeStep.id`, for the same reason `WorkoutSection` carries
    /// `sourceSectionId` one level up — see that field's doc comment.
    var sourceStepId: UUID?

    /// Exists only to satisfy CloudKit's "every relationship needs an inverse" rule for
    /// `StepLog.timeSectionStep` — nothing in the app reads or writes this back-reference.
    @Relationship(inverse: \StepLog.timeSectionStep)
    var stepLogs: [StepLog]?

    var stepType: TimeStepType {
        get { TimeStepType(rawValue: stepTypeRaw) ?? .exercise }
        set { stepTypeRaw = newValue.rawValue }
    }

    var color: PaletteColor? {
        get { colorRaw.flatMap(PaletteColor.init(rawValue:)) }
        set { colorRaw = newValue?.rawValue }
    }

    /// Which side this step works, when the exercise is one-sided. Distinct from a rep
    /// entry's `tracksSides`, which means "log this set twice, once per side" — here the
    /// step *is* one side, and the other side is a separate step.
    var side: SetSide? {
        get { sideRaw.flatMap(SetSide.init(rawValue:)) }
        set { sideRaw = newValue?.rawValue }
    }

    /// The color a step actually displays as. "Never chosen" is a real selection
    /// rather than an absent one: green for exercises, gray for Rest and Get Ready.
    ///
    /// Nothing is stored — `color` stays nil until the user picks one — so this is
    /// purely how a nil *reads*, which keeps export/import round-tripping unchanged
    /// (a never-set step still writes no `color` key).
    var resolvedColor: PaletteColor {
        if let color { return color }
        return stepType == .exercise ? .green : .gray
    }

    /// What this step is called wherever it's listed — the scrub strip's chips, the
    /// all-exercises panel, the builder's rows, history, and the runner's own heading.
    ///
    /// Those five had a private copy of this switch each, which is how the execution type
    /// could reach one and not the others.
    var displayTitle: String {
        switch stepType {
        case .exercise: return ExerciseNaming.title(exercise, side: side, executionType: executionType)
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    init(id: UUID = UUID(), section: WorkoutSection? = nil, sortOrder: Int, stepType: TimeStepType, exercise: Exercise? = nil, durationSeconds: Int, executionType: ExecutionType? = nil) {
        self.id = id
        self.section = section
        self.sortOrder = sortOrder
        self.stepTypeRaw = stepType.rawValue
        self.exercise = exercise
        self.durationSeconds = durationSeconds
        self.colorRaw = nil
        self.executionType = executionType
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
