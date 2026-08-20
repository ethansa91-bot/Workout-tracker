import Foundation
import SwiftData

/// Imports ready-made workouts from the bundled `SeedData/workouts.json` — the starter
/// routines that ship with the app, built out of the same catalog exercises the user
/// already has. Unlike everything in `Seed/`, this is *not* a one-time migration: it's
/// a manual Settings action that adds a fresh copy of every workout in the file each
/// time it's run, so there's no UserDefaults flag and no de-duplication by name.
///
/// Exercises are referenced by name (`workouts.json` carries no ids, matching how
/// `catalog.json` identifies things), so the import is only as good as the catalog on
/// the device. Rather than silently dropping steps whose exercise is missing — which
/// would produce a workout that looks complete but quietly isn't — an unresolvable name
/// aborts the whole import before anything is created.
enum WorkoutImportService {
    static func importBundledWorkouts(context: ModelContext) throws -> WorkoutImportSummary {
        let file: WorkoutsFile = try loadJSON("workouts")
        let resolver = try ExerciseResolver(context: context)

        // Resolve every reference up front. Creating nothing until the whole file is
        // known-good is what makes the abort meaningful — a mid-import failure would
        // otherwise leave half-built workouts behind, since each edit saves as it goes.
        let unknown = resolver.unresolvedNames(in: file.workouts)
        guard unknown.isEmpty else { throw WorkoutImportError.unknownExercises(unknown) }

        var summary = WorkoutImportSummary()
        for seed in file.workouts {
            try importWorkout(seed, resolver: resolver, summary: &summary, context: context)
        }
        return summary
    }

    // MARK: - Building

    private static func importWorkout(
        _ seed: WorkoutSeed,
        resolver: ExerciseResolver,
        summary: inout WorkoutImportSummary,
        context: ModelContext
    ) throws {
        let kind = seed.kind.flatMap(WorkoutKind.init(rawValue:)) ?? .personalized
        let workout = WorkoutEditingService.createWorkout(name: seed.name, kind: kind, context: context)
        summary.workouts += 1

        if let notes = seed.notes?.nilIfBlank {
            try WorkoutEditingService.updateNotes(workout, to: notes, context: context)
        }
        // No editing-service setter for this — and adding one for a flag no imported
        // workout currently sets isn't worth the API surface.
        if seed.isArchived == true {
            workout.isArchived = true
            workout.markDirty()
            try context.save()
        }

        for sectionSeed in seed.sections ?? [] {
            try importSection(sectionSeed, into: workout, resolver: resolver, summary: &summary, context: context)
        }
    }

    private static func importSection(
        _ seed: SectionSeed,
        into workout: Workout,
        resolver: ExerciseResolver,
        summary: inout WorkoutImportSummary,
        context: ModelContext
    ) throws {
        let type = WorkoutSectionType(rawValue: seed.sectionType) ?? .time
        let section = try WorkoutEditingService.addSection(
            to: workout,
            type: type,
            name: seed.name?.nilIfBlank,
            description: seed.sectionDescription?.nilIfBlank,
            context: context
        )
        summary.sections += 1

        switch type {
        case .time:
            try importTimeSteps(seed.timeSteps ?? [], into: section, resolver: resolver, summary: &summary, context: context)
        case .rep:
            try importRepExercises(seed.repExercises ?? [], into: section, resolver: resolver, summary: &summary, context: context)
        case .emom, .amrap:
            // Not produced by workouts.json today; the section is still created so a
            // file that starts using them imports as an empty section rather than
            // failing outright.
            break
        }
    }

    private static func importTimeSteps(
        _ seeds: [TimeStepSeed],
        into section: WorkoutSection,
        resolver: ExerciseResolver,
        summary: inout WorkoutImportSummary,
        context: ModelContext
    ) throws {
        var seeds = seeds

        // `addSection` already created the leading Get Ready step that every Time
        // section is expected to have (see GetReadyStepMigration). The JSON carries its
        // own explicit one, so adopt its duration instead of appending a second — two
        // Get Ready steps would break that invariant.
        if seeds.first?.parsedStepType == .getReady {
            let seed = seeds.removeFirst()
            if let existing = section.sortedTimeSteps.first, existing.stepType == .getReady {
                existing.durationSeconds = seed.durationSeconds
                existing.markDirty()
                section.markDirty()
                try context.save()
                summary.timeSteps += 1
            }
        }

        for seed in seeds {
            let stepType = seed.parsedStepType
            let step = try WorkoutEditingService.addTimeStep(
                to: section,
                stepType: stepType,
                exercise: stepType == .exercise ? resolver.exercise(named: seed.exercise) : nil,
                durationSeconds: seed.durationSeconds,
                context: context
            )
            // Color isn't an init or service parameter — it's set on the returned step.
            if let color = seed.color.flatMap(PaletteColor.init(rawValue:)) {
                step.color = color
                step.markDirty()
                try context.save()
            }
            summary.timeSteps += 1
        }
    }

    private static func importRepExercises(
        _ seeds: [RepExerciseSeed],
        into section: WorkoutSection,
        resolver: ExerciseResolver,
        summary: inout WorkoutImportSummary,
        context: ModelContext
    ) throws {
        for seed in seeds {
            guard let exercise = resolver.exercise(named: seed.exercise) else { continue }
            try WorkoutEditingService.addRepExercise(
                to: section,
                exercise: exercise,
                targetSets: seed.targetSets,
                // nil is meaningful: it means "use the app's default rest".
                customRestSeconds: seed.customRestSeconds,
                trackingMode: seed.trackingMode.flatMap(RepExerciseTrackingMode.init(rawValue:)) ?? .repsWeight,
                headStartSeconds: seed.headStartSeconds ?? 3,
                context: context
            )
            summary.repExercises += 1
        }
    }

    // MARK: - Exercise lookup

    /// Name-based catalog lookup with a forgiving fallback: exact match first, then
    /// trimmed/lowercased. The catalog has entries whose names differ only by stray
    /// whitespace or capitalization from how they're written in `workouts.json`, and
    /// failing those would be a confusing abort over an invisible character.
    private struct ExerciseResolver {
        private let byExactName: [String: Exercise]
        private let byNormalizedName: [String: Exercise]

        init(context: ModelContext) throws {
            let all = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.deletedAt == nil }))
            byExactName = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            byNormalizedName = Dictionary(all.map { (Self.normalize($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        }

        static func normalize(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        func exercise(named name: String?) -> Exercise? {
            guard let name else { return nil }
            return byExactName[name] ?? byNormalizedName[Self.normalize(name)]
        }

        /// Every referenced name that resolves to nothing, sorted and de-duplicated for
        /// display in the failure alert.
        func unresolvedNames(in workouts: [WorkoutSeed]) -> [String] {
            var missing = Set<String>()
            for workout in workouts {
                for section in workout.sections ?? [] {
                    for step in section.timeSteps ?? [] where step.parsedStepType == .exercise {
                        if let name = step.exercise, exercise(named: name) == nil { missing.insert(name) }
                    }
                    for rep in section.repExercises ?? [] {
                        if exercise(named: rep.exercise) == nil { missing.insert(rep.exercise) }
                    }
                }
            }
            return missing.sorted()
        }
    }

    // MARK: - JSON schema

    private struct WorkoutsFile: Decodable {
        let workouts: [WorkoutSeed]
    }

    private struct WorkoutSeed: Decodable {
        let name: String
        let notes: String?
        let kind: String?
        let isArchived: Bool?
        let sections: [SectionSeed]?
    }

    private struct SectionSeed: Decodable {
        let name: String?
        let sectionDescription: String?
        let sectionType: String
        let timeSteps: [TimeStepSeed]?
        let repExercises: [RepExerciseSeed]?
    }

    private struct TimeStepSeed: Decodable {
        let stepType: String
        let durationSeconds: Int
        /// Only present on `exercise` steps.
        let exercise: String?
        let color: String?

        var parsedStepType: TimeStepType { TimeStepType(rawValue: stepType) ?? .exercise }
    }

    private struct RepExerciseSeed: Decodable {
        let exercise: String
        let targetSets: Int
        let trackingMode: String?
        /// Absent means "use the app's default rest", not zero.
        let customRestSeconds: Int?
        let headStartSeconds: Int?
    }

    // MARK: - Loading

    /// Mirrors `CatalogSeedLoader.loadJSON` — same bundle layout, same fallback for a
    /// flattened bundle.
    private static func loadJSON<T: Decodable>(_ resource: String) throws -> T {
        let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "SeedData")
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
        guard let url else { throw SeedDataError.missingResource(resource) }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Result types

struct WorkoutImportSummary {
    var workouts = 0
    var sections = 0
    var timeSteps = 0
    var repExercises = 0
}

enum WorkoutImportError: LocalizedError {
    case unknownExercises([String])

    var errorDescription: String? {
        switch self {
        case .unknownExercises(let names):
            let list = names.map { "• \($0)" }.joined(separator: "\n")
            return """
                Nothing was imported — these exercises aren't in your catalog:

                \(list)

                Add them to the catalog, then import again.
                """
        }
    }
}

private extension String {
    /// Treats the empty strings that fill unused fields in `workouts.json` as "unset",
    /// so sections fall back to their type-based label instead of showing a blank name.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
