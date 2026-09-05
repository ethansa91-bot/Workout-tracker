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
    /// The publisher's `ArchiveSection.id` this section was built from, when it arrived
    /// via a shared-workout download — `Workout.clonedFromWorkoutId` one level deeper.
    /// What lets a later update correlate "this incoming section" against "this existing
    /// one" instead of only ever being able to tell workouts apart. nil for a section
    /// built locally, and for anything downloaded before this existed.
    var sourceSectionId: UUID?

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

    /// EMOM/AMRAP only: a countdown played once before the section's own timer starts.
    /// `0` means none, which is every section written before this existed — so nothing
    /// needs backfilling. A `.time` section doesn't use this: it has a real `.getReady`
    /// `TimeSectionStep` in its step list, which the runner plays like any other step.
    var getReadySeconds: Int = 0

    /// Time/EMOM/AMRAP only: whether the count-in plays again on every repeat pass, or
    /// only before the first.
    ///
    /// The property default and the `init` deliberately disagree. `true` here is what an
    /// existing row reads when SwiftData migrates it, and what an archive written before
    /// the setting existed falls back to — both of which really did replay the count-in,
    /// so that is the honest reading of them. `init` sets `false`, so a section created
    /// from now on starts with it off. Changing this default would silently alter workouts
    /// already built.
    var repeatsGetReadyEachPass: Bool = true

    /// Time/EMOM/AMRAP only: a breather between the last item of one pass and the first of
    /// the next. `0` means none, which is every section written before this existed. Never
    /// played after the final pass — there is nothing left to rest for.
    var sectionRestSeconds: Int = 0

    /// Time/EMOM/AMRAP only: whether the section's timer starts the instant a
    /// session reaches it, or waits for an explicit tap. Unused by `.rep` sections,
    /// which have their own per-set start/stop controls already.
    var autostart: Bool = true

    /// How many times this section's whole contents run back to back — a circuit run
    /// three times through. `1` means no repeat, which is every pre-existing section.
    /// Distinct from `emomRoundCount` (fixed 60s intervals) and AMRAP's tapped lap
    /// tally: this one repeats the section's actual items.
    var repeatCount: Int = 1

    /// Results produced by this section, across every session. Nothing reads the section
    /// side of this — results are always found through the session or by `recordGroupID` —
    /// but CloudKit requires every relationship to declare an inverse, exactly as
    /// `TimeSectionStep.stepLogs` does.
    @Relationship(deleteRule: .nullify, inverse: \SectionResultLog.section)
    var sectionResultLogsStorage: [SectionResultLog]?

    /// EMOM only: rounds run open-ended until the user taps the round counter to stop,
    /// rather than ending at `emomRoundCount`. `false` is every section written before
    /// this existed. A to-failure section always runs a single pass — an open-ended
    /// section has no end for a repeat to start after — so enabling it clamps
    /// `repeatCount` to 1.
    var emomToFailure: Bool = false

    /// EMOM/AMRAP only: this section's round count is a personal record.
    var tracksRecord: Bool = false

    /// The identity that record is filed under, minted when `tracksRecord` is first
    /// turned on and copied verbatim by every deep copy — so a template imported into
    /// three workouts feeds one record rather than three. Deliberately not `id`, which
    /// every copy re-mints, and deliberately not a relationship: a plain UUID survives
    /// the template being deleted and needs no CloudKit inverse.
    var recordGroupID: UUID?

    /// Stamped the first time a result is filed against `recordGroupID`, which is what
    /// locks the section's structure — changing the work would change what the record
    /// means. A cheap stored hint for the UI only; `WorkoutEditingService` re-checks
    /// against the live record (it has a context), so a stale flag can never be the only
    /// thing holding the lock.
    var recordLockedAt: Date?

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
        // An open-ended EMOM has no end for a second pass to begin after, so it is
        // always a single pass whatever the stored value says. Enforced here rather
        // than only at the setter so a section that had a repeat *before* to-failure
        // was turned on can't strand a session waiting for a pass that never ends.
        guard !isToFailure else { return 1 }
        return max(1, repeatCount)
    }

    /// Whether this section actually runs open-ended. Reads the type as well as the flag,
    /// so a stale `emomToFailure` on a non-EMOM section — which nothing should produce,
    /// but which an old archive or a hand-edited seed file could — can't quietly suppress
    /// that section's repeats.
    var isToFailure: Bool {
        sectionType == .emom && emomToFailure
    }

    /// Whether a record can be tracked here at all: an AMRAP always can, an EMOM only
    /// once its rounds are open-ended. A fixed ten-round EMOM you finish records ten
    /// every time, which is a record that can never move.
    var canTrackRecord: Bool {
        sectionType == .amrap || isToFailure
    }

    init(id: UUID = UUID(), workout: Workout? = nil, sortOrder: Int, sectionType: WorkoutSectionType, name: String? = nil, description: String? = nil) {
        self.id = id
        self.workout = workout
        self.sortOrder = sortOrder
        self.sectionTypeRaw = sectionType.rawValue
        self.name = name
        self.sectionDescription = description
        // Off for a newly built section; see the property's own note for why the stored
        // default above says otherwise. Every importer and cloner assigns this explicitly
        // right after construction, so none of them inherit this.
        self.repeatsGetReadyEachPass = false
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var sortedTimeSteps: [TimeSectionStep] {
        timeSteps.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The steps the runner actually plays on a given 0-based pass.
    ///
    /// A Get Ready of 0 is not a zero-length step, it is no step: left in, it still takes a
    /// scrub-strip chip, a slot in the progress bar and a row in history, and just flashes
    /// past. And one that doesn't repeat is simply absent after the first pass.
    ///
    /// Every consumer reads this rather than `sortedTimeSteps` — the runner, the scrub
    /// strip behind it, the progress count and the all-exercises list each used to derive
    /// their own view of the list, which is how they could disagree about what is playing.
    func runnableTimeSteps(pass: Int = 0) -> [TimeSectionStep] {
        sortedTimeSteps.filter { step in
            guard step.stepType == .getReady else { return true }
            guard step.durationSeconds > 0 else { return false }
            return pass == 0 || repeatsGetReadyEachPass
        }
    }

    /// The count-in this pass plays — the grid runners' equivalent of the filter above,
    /// since they hold their Get Ready as a duration rather than as a step. Named apart
    /// from the stored `getReadySeconds` so a call site can't read one and mean the other.
    func countInSeconds(pass: Int) -> Int {
        guard pass == 0 || repeatsGetReadyEachPass else { return 0 }
        return getReadySeconds
    }

    /// Whether a rest follows the pass just finished. The last pass has nothing to rest
    /// for, so it never does.
    func sectionRest(after pass: Int) -> Int {
        guard sectionRestSeconds > 0, pass + 1 < effectiveRepeatCount else { return 0 }
        return sectionRestSeconds
    }

    var sortedRepExercises: [RepSectionExercise] {
        repExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedQuickExercises: [SectionExerciseEntry] {
        quickExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Organisational labels, offered only on templates — a section inside a workout is
    /// found through that workout, which carries its own.
    @Relationship(inverse: \WorkoutTag.sectionsStorage)
    var tagsStorage: [WorkoutTag]?
    var tags: [WorkoutTag] {
        get { tagsStorage ?? [] }
        set { tagsStorage = newValue }
    }

    var sortedTags: [WorkoutTag] {
        tags.filter { $0.deletedAt == nil }.sorted { $0.name < $1.name }
    }

    /// A section with no parent workout is a reusable template, imported (deep-copied)
    /// into a real workout via `WorkoutSectionCloningService.importTemplate`.
    var isTemplate: Bool {
        workout == nil
    }

    /// A record-tracking section locks once a result has been filed against it, and that
    /// applies to templates too — the template *is* the record's identity, so editing it
    /// afterwards would silently redefine every past entry. Otherwise a template is
    /// unlocked (there's no session history to protect) and an in-workout section defers
    /// entirely to its parent workout's lock state.
    ///
    /// The stored stamp is a display hint. `WorkoutEditingService` is the enforcement
    /// point and re-derives this from the live record, so a copy made before the first
    /// result — carrying the same `recordGroupID` but no stamp — is still refused.
    var isLocked: Bool {
        if tracksRecord, recordLockedAt != nil { return true }
        guard let workout else { return false }
        return workout.isLocked
    }
}
