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
            kind: workout.kind.rawValue,
            isArchived: workout.isArchived,
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
            autostart: section.autostart,
            repeatCount: section.repeatCount,
            emomRoundCount: section.sectionType == .emom ? section.emomRoundCount : nil,
            amrapDurationSeconds: section.sectionType == .amrap ? section.amrapDurationSeconds : nil,
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
                ? section.sortedQuickExercises.map { QuickExerciseOut(exercise: exerciseKey($0.exercise) ?? "") }
                : nil
        )
    }

    private static func timeStepOut(_ step: TimeSectionStep) -> TimeStepOut {
        TimeStepOut(
            stepType: step.stepType.rawValue,
            durationSeconds: step.durationSeconds,
            exercise: exerciseKey(step.exercise),
            color: step.color?.rawValue
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
            preferredEquipment: entry.preferredEquipment?.name
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
        let kind: String
        let isArchived: Bool
        let sections: [SectionOut]
    }

    private struct SectionOut: Encodable {
        let name: String?
        let sectionDescription: String?
        let sectionType: String
        let autostart: Bool
        let repeatCount: Int
        let emomRoundCount: Int?
        let amrapDurationSeconds: Int?
        let timeSteps: [TimeStepOut]?
        let repExercises: [RepExerciseOut]?
        let quickExercises: [QuickExerciseOut]?
    }

    private struct TimeStepOut: Encodable {
        let stepType: String
        let durationSeconds: Int
        let exercise: String?
        let color: String?
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
    }

    private struct QuickExerciseOut: Encodable {
        let exercise: String
    }
}
