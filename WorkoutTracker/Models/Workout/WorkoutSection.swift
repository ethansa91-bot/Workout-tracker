import Foundation
import SwiftData

enum WorkoutSectionType: String, Codable {
    case time, rep, emom, amrap
}

extension WorkoutSectionType {
    var iconSymbolName: String {
        switch self {
        case .time: return "timer"
        case .rep: return "list.number"
        case .emom: return "repeat"
        case .amrap: return "flame"
        }
    }

    var fallbackSectionName: String {
        switch self {
        case .time: return "Follow Along Section"
        case .rep: return "Rep Section"
        case .emom: return "EMOM Section"
        case .amrap: return "AMRAP Section"
        }
    }

    /// Short label for a type pill/badge — e.g. `SectionTemplatesView`'s row pill and
    /// the section editors' header.
    var pillLabel: String {
        switch self {
        case .time: return "Follow Along"
        case .rep: return "Rep"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        }
    }
}

@Model
final class WorkoutSection: SyncableModel, Orderable {
    var id: UUID = UUID()
    var workout: Workout?
    var sortOrder: Int = 0
    var name: String?
    /// Optional description, editable on any section — in-workout or template alike.
    /// Shown in the templates list and the "Import Template" picker for templates.
    /// Named `sectionDescription`, not `description` — SwiftData's `@Model` macro
    /// reserves the `description` property name.
    var sectionDescription: String?
    var sectionTypeRaw: String = WorkoutSectionType.time.rawValue
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// Populated only when `sectionType == .time`.
    @Relationship(deleteRule: .cascade, inverse: \TimeSectionStep.section)
    var timeStepsStorage: [TimeSectionStep]?
    var timeSteps: [TimeSectionStep] {
        get { timeStepsStorage ?? [] }
        set { timeStepsStorage = newValue }
    }

    /// Populated only when `sectionType == .rep`.
    @Relationship(deleteRule: .cascade, inverse: \RepSectionExercise.section)
    var repExercisesStorage: [RepSectionExercise]?
    var repExercises: [RepSectionExercise] {
        get { repExercisesStorage ?? [] }
        set { repExercisesStorage = newValue }
    }

    /// Populated only when `sectionType == .emom` or `.amrap` — both are just a short
    /// list of exercises shown all at once during the session, no per-exercise
    /// settings, unlike `repExercises`.
    @Relationship(deleteRule: .cascade, inverse: \SectionExerciseEntry.section)
    var quickExercisesStorage: [SectionExerciseEntry]?
    var quickExercises: [SectionExerciseEntry] {
        get { quickExercisesStorage ?? [] }
        set { quickExercisesStorage = newValue }
    }

    /// EMOM only: number of 1-minute rounds.
    var emomRoundCount: Int = 10

    /// AMRAP only: total countdown duration, in seconds.
    var amrapDurationSeconds: Int = 720

    /// Time/EMOM/AMRAP only: whether the section's timer starts the instant a
    /// session reaches it, or waits for an explicit tap. Unused by `.rep` sections,
    /// which have their own per-set start/stop controls already.
    var autostart: Bool = true

    /// How many times this section's whole contents run back to back — a circuit run
    /// three times through. `1` means no repeat, which is every pre-existing section.
    /// Distinct from `emomRoundCount` (fixed 60s intervals) and AMRAP's tapped lap
    /// tally: this one repeats the section's actual items.
    var repeatCount: Int = 1

    var sectionType: WorkoutSectionType {
        get { WorkoutSectionType(rawValue: sectionTypeRaw) ?? .time }
        set { sectionTypeRaw = newValue.rawValue }
    }

    /// The section's name, or its type-based fallback — the one place this idiom
    /// lives, rather than being respelled at each call site.
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return sectionType.fallbackSectionName
    }

    /// Repeat counts below 1 would stall a session, so the runner always reads this
    /// rather than the raw stored value.
    var effectiveRepeatCount: Int {
        max(1, repeatCount)
    }

    init(id: UUID = UUID(), workout: Workout? = nil, sortOrder: Int, sectionType: WorkoutSectionType, name: String? = nil, description: String? = nil) {
        self.id = id
        self.workout = workout
        self.sortOrder = sortOrder
        self.sectionTypeRaw = sectionType.rawValue
        self.name = name
        self.sectionDescription = description
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var sortedTimeSteps: [TimeSectionStep] {
        timeSteps.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedRepExercises: [RepSectionExercise] {
        repExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedQuickExercises: [SectionExerciseEntry] {
        quickExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// A section with no parent workout is a reusable template, imported (deep-copied)
    /// into a real workout via `WorkoutSectionCloningService.importTemplate`.
    var isTemplate: Bool {
        workout == nil
    }

    /// Templates are never locked (there's no session history to protect); an
    /// in-workout section defers entirely to its parent workout's lock state.
    var isLocked: Bool {
        guard let workout else { return false }
        return workout.isLocked
    }
}
