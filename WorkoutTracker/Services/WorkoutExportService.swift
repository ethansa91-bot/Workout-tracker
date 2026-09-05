import Foundation
import SwiftData

/// Writes workouts and section templates back out in the same JSON schema
/// `WorkoutImportService` reads, so an exported file can be dropped in as a seed file.
///
/// The DTOs here are deliberately a parallel `Encodable` set rather than a shared
/// `Codable` reuse of the import ones: the contract between the two sides is the JSON
/// itself, and keeping them separate means the reader can stay lenient (every field
/// optional, unknown keys ignored) while the writer stays explicit about what it emits.
@MainActor
enum WorkoutExportService {

    // MARK: - Public

    /// `workouts` in the same shape as the bundled seed, plus a `templates` key holding
    /// standalone sections — those have no parent workout, so they have nowhere to live
    /// under `workouts`.
    static func makeJSON(workouts: [Workout], templates: [WorkoutSection]) throws -> Data {
        let file = ExportFile(
            workouts: workouts.map(workoutOut),
            templates: templates
                .filter { $0.isTemplate && $0.deletedAt == nil }
                .map(sectionOut)
        )

        let encoder = JSONEncoder()
        // Matches the hand-written seed file's formatting so the two diff cleanly.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    /// Every template in the store, for callers that always export all of them.
    static func allTemplates(context: ModelContext) -> [WorkoutSection] {
        let all = (try? context.fetch(FetchDescriptor<WorkoutSection>())) ?? []
        return all
            .filter { $0.isTemplate && $0.deletedAt == nil }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    // MARK: - Mapping

    private static func workoutOut(_ workout: Workout) -> WorkoutOut {
        WorkoutOut(
            name: workout.name,
            notes: workout.notes,
            isArchived: workout.isArchived,
            tags: workout.sortedTags.isEmpty ? nil : workout.sortedTags.map(\.name),
            sections: workout.sortedSections.map(sectionOut)
        )
    }

    private static func sectionOut(_ section: WorkoutSection) -> SectionOut {
        // The `sorted…` accessors both order by sortOrder and drop soft-deleted rows,
        // so the export never carries a tombstone or a shuffled list.
        SectionOut(
            name: section.name,
            sectionDescription: section.sectionDescription,
            sectionType: section.sectionType.rawValue,
            tags: section.sortedTags.isEmpty ? nil : section.sortedTags.map(\.name),
            autostart: section.autostart,
            repeatCount: section.repeatCount,
            emomRoundCount: section.sectionType == .emom ? section.emomRoundCount : nil,
            // Both omitted at their defaults, so a section using neither writes the same
            // file it always did. The record *identity* is deliberately absent from this
            // format: seed files are shared starting points, not one user's record.
            emomToFailure: section.emomToFailure ? true : nil,
            tracksRecord: section.tracksRecord ? true : nil,
            amrapDurationSeconds: section.sectionType == .amrap ? section.amrapDurationSeconds : nil,
            // EMOM and AMRAP only — a Time section's get-ready is a real step and rides
            // along in `timeSteps` below. Omitted at 0 so sections without one write the
            // same file they always did.
            getReadySeconds: (section.sectionType == .emom || section.sectionType == .amrap) && section.getReadySeconds > 0
                ? section.getReadySeconds
                : nil,
            // Both omitted at their defaults, so a section that uses neither writes the
            // same file it always did.
            repeatsGetReadyEachPass: section.repeatsGetReadyEachPass ? nil : false,
            sectionRestSeconds: section.sectionRestSeconds > 0 ? section.sectionRestSeconds : nil,
            // Get Ready is emitted along with everything else: the seed files carry it,
            // and the importer only synthesizes one when the first step isn't already
            // a getReady, so round-tripping can't double it up.
            timeSteps: section.sectionType == .time
                ? section.sortedTimeSteps.map(timeStepOut)
                : nil,
            repExercises: section.sectionType == .rep
                ? section.sortedRepExercises.map(repExerciseOut)
                : nil,
            quickExercises: (section.sectionType == .emom || section.sectionType == .amrap)
                ? section.sortedQuickExercises.map { QuickExerciseOut(exercise: exerciseKey($0.exercise) ?? "", executionType: $0.executionType?.name, reps: $0.targetReps > 0 ? $0.targetReps : nil, side: $0.side?.rawValue) }
                : nil
        )
    }

    private static func timeStepOut(_ step: TimeSectionStep) -> TimeStepOut {
        TimeStepOut(
            stepType: step.stepType.rawValue,
            durationSeconds: step.durationSeconds,
            exercise: exerciseKey(step.exercise),
            color: step.color?.rawValue,
            executionType: step.executionType?.name,
            side: step.side?.rawValue,
            preferredEquipment: step.preferredEquipment?.name,
            prefersBodyweight: step.prefersBodyweight ? true : nil
        )
    }

    private static func repExerciseOut(_ entry: RepSectionExercise) -> RepExerciseOut {
        RepExerciseOut(
            exercise: exerciseKey(entry.exercise) ?? "",
            targetSets: entry.targetSets,
            trackingMode: entry.trackingMode.rawValue,
            customRestSeconds: entry.customRestSeconds,
            headStartSeconds: entry.headStartSeconds,
            allowsBodyweight: entry.allowsBodyweight,
            tracksSides: entry.tracksSides,
            preferredEquipment: entry.preferredEquipment?.name,
            prefersBodyweight: entry.prefersBodyweight,
            executionType: entry.executionType?.name,
            progressionEnabled: entry.progressionEnabled
        )
    }

    /// **`name`, never `displayName`.** `WorkoutImportService.ExerciseResolver` looks
    /// exercises up by `name` (exact, then case/whitespace-normalized); `displayName`
    /// prefers `label` when one is set, so writing it here would produce a file that
    /// reads fine but fails to resolve every labelled exercise on import.
    private static func exerciseKey(_ exercise: Exercise?) -> String? {
        exercise?.name
    }

    // MARK: - JSON schema (mirror of WorkoutImportService's seed types)

    private struct ExportFile: Encodable {
        let workouts: [WorkoutOut]
        let templates: [SectionOut]
    }

    private struct WorkoutOut: Encodable {
        let name: String
        let notes: String?
        let isArchived: Bool
        /// By name, like every other reference in this format — it is hand-editable and
        /// resolves against the reader's own library.
        let tags: [String]?
        let sections: [SectionOut]
    }

    private struct SectionOut: Encodable {
        let name: String?
        let sectionDescription: String?
        let sectionType: String
        /// Written for templates, which is the only kind of section that carries tags.
        /// The importer has no standalone-template path to apply it to, so this is
        /// currently write-only — the format's reader ignores keys it has no use for.
        let tags: [String]?
        let autostart: Bool
        let repeatCount: Int
        let emomRoundCount: Int?
        /// Written only when set — absent means a fixed number of rounds.
        let emomToFailure: Bool?
        /// Written only when set. Carries the *intent* to track a record, not the record
        /// identity: an imported section mints its own, so two people running the same
        /// seed each keep their own history.
        let tracksRecord: Bool?
        let amrapDurationSeconds: Int?
        let getReadySeconds: Int?
        /// Written only when false — absent means the count-in plays before every pass.
        let repeatsGetReadyEachPass: Bool?
        /// Seconds between passes. Omitted when there is no rest.
        let sectionRestSeconds: Int?
        let timeSteps: [TimeStepOut]?
        let repExercises: [RepExerciseOut]?
        let quickExercises: [QuickExerciseOut]?
    }

    private struct TimeStepOut: Encodable {
        let stepType: String
        let durationSeconds: Int
        let exercise: String?
        let color: String?
        /// By name, like `preferredEquipment` and for the same reason: this format is
        /// hand-editable and resolves against the reader's own catalog.
        let executionType: String?
        /// "left"/"right", omitted for a step worked both sides.
        let side: String?
        /// By name, like a rep entry's. Omitted when the step names none.
        let preferredEquipment: String?
        /// Omitted when false, so a step with no load writes the same file it always did.
        let prefersBodyweight: Bool?
    }

    private struct RepExerciseOut: Encodable {
        let exercise: String
        let targetSets: Int
        let trackingMode: String
        let customRestSeconds: Int?
        let headStartSeconds: Int
        let allowsBodyweight: Bool
        let tracksSides: Bool
        let preferredEquipment: String?
        let prefersBodyweight: Bool
        let executionType: String?
        let progressionEnabled: Bool
    }

    private struct QuickExerciseOut: Encodable {
        let exercise: String
        let executionType: String?
        /// Omitted when unset, so a workout with no rep targets writes the same file it
        /// always did.
        let reps: Int?
        /// "left"/"right", omitted for an entry worked both sides.
        let side: String?
    }
}
