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
        // A `kind` key from an older export is read and discarded: workouts no longer
        // have a type, so such a file imports as an ordinary workout whose sections
        // carry the only type that matters.
        let workout = WorkoutEditingService.createWorkout(name: seed.name, context: context)
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

        let tags = resolveTags(seed.tags, context: context)
        if !tags.isEmpty {
            try WorkoutEditingService.setTags(tags, on: workout, context: context)
        }

        for sectionSeed in seed.sections ?? [] {
            try importSection(sectionSeed, into: workout, resolver: resolver, summary: &summary, context: context)
        }
    }

    /// Maps tag names onto rows, creating what doesn't exist yet.
    ///
    /// Case-insensitive so an imported "Push" joins the user's existing "push" instead of
    /// standing beside it — two spellings of one word would split the filter they exist to
    /// serve, the same reason the tag sheet dedupes on entry.
    private static func resolveTags(_ names: [String]?, context: ModelContext) -> [WorkoutTag] {
        guard let names, !names.isEmpty else { return [] }
        let existing = (try? context.fetch(FetchDescriptor<WorkoutTag>())) ?? []
        var live = existing.filter { $0.deletedAt == nil }

        var resolved: [WorkoutTag] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let match = live.first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) {
                if !resolved.contains(where: { $0.id == match.id }) { resolved.append(match) }
                continue
            }
            let created = WorkoutTag(name: name)
            context.insert(created)
            live.append(created)
            resolved.append(created)
        }
        return resolved
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

        // Both are omitted from the file when they match the app's own defaults, so an
        // absent key means "leave it alone" rather than "reset it".
        if let autostart = seed.autostart, type != .rep {
            try WorkoutEditingService.updateAutostart(section, to: autostart, context: context)
        }
        if let repeatCount = seed.repeatCount, repeatCount > 1 {
            try WorkoutEditingService.updateRepeatCount(section, to: repeatCount, context: context)
        }
        // Unconditional, and `true` when the key is absent: the writer omits this whenever
        // it is on, so "missing" means on rather than "leave it alone". Left conditional,
        // a file written with it on would import with it off, because a freshly built
        // section now starts off.
        try WorkoutEditingService.updateRepeatsGetReady(
            section, to: seed.repeatsGetReadyEachPass ?? true, context: context
        )
        if let rest = seed.sectionRestSeconds, rest > 0 {
            try WorkoutEditingService.updateSectionRest(section, to: min(300, rest), context: context)
        }

        switch type {
        case .time:
            try importTimeSteps(seed.timeSteps ?? [], into: section, resolver: resolver, summary: &summary, context: context)
        case .rep:
            try importRepExercises(seed.repExercises ?? [], into: section, resolver: resolver, summary: &summary, context: context)
        case .emom:
            // Before the round count: to-failure hides it, and the setter clamps the
            // repeat, so applying it second would silently discard a rounds value the
            // file did supply for a section that later turns out to be fixed.
            if seed.emomToFailure == true {
                try WorkoutEditingService.updateEmomToFailure(section, to: true, context: context)
            }
            if let rounds = seed.emomRoundCount {
                try WorkoutEditingService.updateEmomRoundCount(section, to: rounds, context: context)
            }
            try applyGetReady(seed.getReadySeconds, to: section, context: context)
            try applyTracksRecord(seed.tracksRecord, to: section, context: context)
            try importQuickExercises(seed.quickExercises ?? [], into: section, resolver: resolver, summary: &summary, context: context)
        case .amrap:
            if let seconds = seed.amrapDurationSeconds {
                try WorkoutEditingService.updateAmrapDuration(section, to: seconds, context: context)
            }
            try applyGetReady(seed.getReadySeconds, to: section, context: context)
            try applyTracksRecord(seed.tracksRecord, to: section, context: context)
            try importQuickExercises(seed.quickExercises ?? [], into: section, resolver: resolver, summary: &summary, context: context)
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
            if let type = executionType(named: seed.executionType, on: step.exercise) {
                step.executionType = type
                step.markDirty()
                try context.save()
            }
            if let side = side(named: seed.side, on: step.exercise) {
                step.side = side
                step.markDirty()
                try context.save()
            }
            if let name = seed.preferredEquipment,
               let equipment = step.exercise?.weightedEquipmentOptions.first(where: {
                   $0.name.compare(name, options: .caseInsensitive) == .orderedSame
               }) {
                step.preferredEquipment = equipment
                step.markDirty()
                try context.save()
            }
            if seed.prefersBodyweight == true, step.exercise?.allowsBodyweightSource == true {
                step.prefersBodyweight = true
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
            let entry = try WorkoutEditingService.addRepExercise(
                to: section,
                exercise: exercise,
                targetSets: seed.targetSets,
                // nil is meaningful: it means "use the app's default rest".
                customRestSeconds: seed.customRestSeconds,
                trackingMode: seed.trackingMode.flatMap(RepExerciseTrackingMode.init(rawValue:)) ?? .repsWeight,
                headStartSeconds: seed.headStartSeconds ?? 3,
                // Both are only meaningful when the catalog exercise allows them; the
                // file shouldn't be able to turn on an option the exercise forbids.
                allowsBodyweight: (seed.allowsBodyweight ?? false) && exercise.allowsBodyweight,
                tracksSides: (seed.tracksSides ?? false) && exercise.isOneSided,
                context: context
            )
            // Not an `addRepExercise` parameter — set on the returned entry, the same
            // way `importTimeSteps` sets a step's color. Resolved against the
            // exercise's own equipment so a stale name is ignored rather than applied.
            if let name = seed.preferredEquipment,
               let equipment = exercise.equipmentItems.first(where: { $0.name == name && $0.isWeighted }) {
                entry.preferredEquipment = equipment
                entry.markDirty()
                try context.save()
            }
            // Same guard as `allowsBodyweight` above: only honored when the exercise
            // itself can be done unloaded.
            if seed.prefersBodyweight == true, exercise.allowsBodyweightSource {
                entry.prefersBodyweight = true
                entry.markDirty()
                try context.save()
            }
            if let type = executionType(named: seed.executionType, on: exercise) {
                entry.executionType = type
                entry.markDirty()
                try context.save()
            }
            if seed.progressionEnabled == false {
                entry.progressionEnabled = false
                entry.markDirty()
                try context.save()
            }
            summary.repExercises += 1
        }
    }

    /// Resolved against the exercise's own types, so a name the catalog doesn't have —
    /// or has but hasn't attached here — is ignored rather than applied. The same rule
    /// `preferredEquipment` follows, and the reason this format can stay hand-written.
    private static func executionType(named name: String?, on exercise: Exercise?) -> ExecutionType? {
        guard let name, let exercise else { return nil }
        return exercise.executionTypes.first {
            $0.deletedAt == nil && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    /// A side only applies to an exercise the catalog marks one-sided — the same
    /// capability rule `tracksSides` follows, so a hand-written file can't pin "Left"
    /// onto a movement whose own pickers would never offer it.
    private static func side(named raw: String?, on exercise: Exercise?) -> SetSide? {
        guard let raw, exercise?.isOneSided == true else { return nil }
        return SetSide(rawValue: raw.lowercased())
    }

    /// EMOM and AMRAP hold their get-ready as a plain duration rather than as a step, so
    /// there is no `addTimeStep` to route through — it is written straight to the section.
    private static func applyGetReady(_ seconds: Int?, to section: WorkoutSection, context: ModelContext) throws {
        guard let seconds, seconds > 0 else { return }
        section.getReadySeconds = min(300, seconds)
        section.markDirty()
        try context.save()
    }

    /// Turns on record tracking when the file asks for it, minting a fresh identity via
    /// the editing service — the seed format carries the intent, not the publisher's own
    /// `recordGroupID`, so two people importing the same file each keep their own record.
    private static func applyTracksRecord(_ tracks: Bool?, to section: WorkoutSection, context: ModelContext) throws {
        guard tracks == true else { return }
        try WorkoutEditingService.updateTracksRecord(section, to: true, context: context)
    }

    private static func importQuickExercises(
        _ seeds: [QuickExerciseSeed],
        into section: WorkoutSection,
        resolver: ExerciseResolver,
        summary: inout WorkoutImportSummary,
        context: ModelContext
    ) throws {
        for seed in seeds {
            guard let exercise = resolver.exercise(named: seed.exercise) else { continue }
            let entry = try WorkoutEditingService.addQuickExercise(to: section, exercise: exercise, context: context)
            // Set on the returned entry rather than passed in, the same way a rep entry's
            // equipment and a time step's color are.
            if let type = executionType(named: seed.executionType, on: exercise) {
                entry.executionType = type
                entry.markDirty()
                try context.save()
            }
            if let reps = seed.reps, reps > 0 {
                entry.targetReps = reps
                entry.markDirty()
                try context.save()
            }
            if let side = side(named: seed.side, on: exercise) {
                entry.side = side
                entry.markDirty()
                try context.save()
            }
            summary.quickExercises += 1
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
        /// Tag names. Created on demand and matched case-insensitively, the way a stale
        /// `executionType` is ignored rather than aborting — a tag is organisational, so
        /// an unfamiliar one is worth adopting, not worth refusing the whole file over.
        let tags: [String]?
        let sections: [SectionSeed]?
    }

    private struct SectionSeed: Decodable {
        let name: String?
        let sectionDescription: String?
        let sectionType: String
        /// Time/EMOM/AMRAP only — absent means the app's default (start on arrival).
        let autostart: Bool?
        /// Absent (or 1) means the section runs once.
        let repeatCount: Int?
        let emomRoundCount: Int?
        /// EMOM only — absent means a fixed number of rounds.
        let emomToFailure: Bool?
        /// EMOM/AMRAP only — absent means the section tracks no record. The identity is
        /// minted locally on import, so each importer keeps their own history.
        let tracksRecord: Bool?
        let amrapDurationSeconds: Int?
        /// EMOM/AMRAP only — absent means no get-ready phase, which is what every file
        /// written before it existed says by omission.
        let getReadySeconds: Int?
        /// Absent means the count-in plays before every pass, the model's own default.
        let repeatsGetReadyEachPass: Bool?
        /// Seconds between passes. Absent means none.
        let sectionRestSeconds: Int?
        let timeSteps: [TimeStepSeed]?
        let repExercises: [RepExerciseSeed]?
        let quickExercises: [QuickExerciseSeed]?
    }

    private struct QuickExerciseSeed: Decodable {
        /// Absent means no target, which is what every file written before reps existed
        /// says by omission.
        let reps: Int?
        /// Name of the execution type, resolved against the exercise's own types and
        /// ignored when stale — same rule as everywhere else in this format.
        let executionType: String?
        /// "left"/"right". Absent means both sides, and it is ignored when the exercise
        /// isn't one-sided — the same capability rule `tracksSides` follows.
        let side: String?
        let exercise: String
    }

    private struct TimeStepSeed: Decodable {
        let stepType: String
        let durationSeconds: Int
        /// Only present on `exercise` steps.
        let exercise: String?
        let color: String?
        /// Name of the execution type this step is performed as. Ignored when the
        /// exercise doesn't carry it, the same way a stale `preferredEquipment` is.
        let executionType: String?
        /// "left"/"right". Absent means both sides, and it is ignored when the exercise
        /// isn't one-sided — the same capability rule `tracksSides` follows.
        let side: String?
        /// Name of the weighted equipment this workout holds the step with. Absent falls
        /// back to the exercise's own resolution.
        let preferredEquipment: String?
        /// The step is performed unloaded, ignoring `preferredEquipment`.
        let prefersBodyweight: Bool?

        var parsedStepType: TimeStepType { TimeStepType(rawValue: stepType) ?? .exercise }
    }

    private struct RepExerciseSeed: Decodable {
        let exercise: String
        let targetSets: Int
        let trackingMode: String?
        /// Absent means "use the app's default rest", not zero.
        let customRestSeconds: Int?
        let headStartSeconds: Int?
        let allowsBodyweight: Bool?
        let tracksSides: Bool?
        /// Name of the weighted equipment this workout uses for the exercise, when it
        /// has more than one. Absent falls back to the exercise's own resolution.
        let preferredEquipment: String?
        /// Bodyweight is this entry's default load, ignoring `preferredEquipment`.
        let prefersBodyweight: Bool?
        /// Name of the execution type this workout performs the exercise as.
        let executionType: String?
        /// Absent means on, which is the model's own default — an older file predates the
        /// setting and its entries should follow their ladders like any other.
        let progressionEnabled: Bool?
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
    var quickExercises = 0
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
