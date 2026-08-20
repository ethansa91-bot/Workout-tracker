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
    var updatedAt: Date = Date.now
    var deletedAt: Date?

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

    /// The color an exercise step displays as in the section/workout lists — whatever
    /// was manually chosen, or green by default when nothing was. `nil` for rest/get
    /// ready steps, which have no color picker and stay plain gray in those lists.
    /// The live scrub strip during a session uses raw `color` instead (not this) —
    /// there, an unset color means the old plain gray/no-border look, not a green
    /// default; only an explicit choice gets the colored treatment.
    var effectiveColor: PaletteColor? {
        guard stepType == .exercise else { return nil }
        return color ?? .green
    }

    init(id: UUID = UUID(), section: WorkoutSection? = nil, sortOrder: Int, stepType: TimeStepType, exercise: Exercise? = nil, durationSeconds: Int) {
        self.id = id
        self.section = section
        self.sortOrder = sortOrder
        self.stepTypeRaw = stepType.rawValue
        self.exercise = exercise
        self.durationSeconds = durationSeconds
        self.colorRaw = nil
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
