import Foundation
import SwiftData
import SwiftUI

enum WorkoutEditingError: LocalizedError {
    case locked
    /// A section locked by its own record rather than by its parent workout. Its own case
    /// because the advice differs: cloning the workout doesn't help, since every copy of a
    /// tracked section feeds the same record on purpose.
    case recordLocked

    var errorDescription: String? {
        switch self {
        case .locked:
            return "This workout has already been used in a session, so its sections can no longer be changed. Clone it to restructure it."
        case .recordLocked:
            return "This section holds a record, so changing it would change what that record means. Delete the record from the Records tab to edit it again, or build a new section."
        }
    }
}

/// Every mutation to a workout's structure goes through here, not directly through
/// SwiftData — the one thing every structural entry point has in common is checking
/// `workout.isLocked` first. SwiftData itself has no way to enforce that.
///
/// "Structure" is the operative word: `rename` and `updateNotes` are exempt, because
/// what the lock protects is the meaning of past sessions, and neither changes it.
enum WorkoutEditingService {
    static func createWorkout(name: String, context: ModelContext) -> Workout {
        let workout = Workout(name: name)
        context.insert(workout)
        try? context.save()
        return workout
    }

    /// Deliberately unguarded by `requireUnlocked`: the lock protects what a past
    /// session *means*, and renaming doesn't change that — the session still points at
    /// the same workout, doing the same thing. Only structure is locked.
    static func rename(_ workout: Workout, to name: String, context: ModelContext) throws {
        workout.name = name
        workout.markDirty()
        try context.save()
    }

    /// Unguarded for the same reason as `rename`: a tag is a label you file the workout
    /// under, not part of what a past session did. Locking it would mean a workout became
    /// permanently unfileable the moment you first ran it, which is precisely backwards —
    /// the workouts worth organising are the ones you've actually used.
    ///
    /// Takes the whole set rather than add/remove, because the picker edits a selection.
    static func setTags(_ tags: [WorkoutTag], on workout: Workout, context: ModelContext) throws {
        workout.tags = tags
        workout.markDirty()
        try context.save()
    }

    /// Templates are never locked, so this needs no guard for a different reason — but it
    /// lives here beside its workout twin so both are found together.
    static func setTags(_ tags: [WorkoutTag], on section: WorkoutSection, context: ModelContext) throws {
        section.tags = tags
        section.markDirty()
        try context.save()
    }

    /// Unguarded for the same reason as `rename` — a description is commentary, not
    /// structure.
    static func updateNotes(_ workout: Workout, to notes: String?, context: ModelContext) throws {
        workout.notes = notes
        workout.markDirty()
        try context.save()
    }

    // MARK: - Sections

    static func addSection(to workout: Workout, type: WorkoutSectionType, name: String? = nil, description: String? = nil, context: ModelContext) throws -> WorkoutSection {
        try requireUnlocked(workout)
        let nextOrder = (workout.sections.map(\.sortOrder).max() ?? -1) + 1
        let section = WorkoutSection(workout: workout, sortOrder: nextOrder, sectionType: type, name: name, description: description)
        context.insert(section)
        if type == .time {
            let getReady = TimeSectionStep(section: section, sortOrder: 0, stepType: .getReady, exercise: nil, durationSeconds: 15)
            context.insert(getReady)
        }
        workout.markDirty()
        try context.save()
        return section
    }

    static func deleteSection(_ section: WorkoutSection, from workout: Workout, context: ModelContext) throws {
        try requireUnlocked(workout)
        SyncDeletion.delete(section, context: context)
        WorkoutSection.resequence(workout.sortedSections.filter { $0.id != section.id })
        workout.markDirty()
        try context.save()
    }

    static func moveSections(in workout: Workout, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        try requireUnlocked(workout)
        var sections = workout.sortedSections
        sections.move(fromOffsets: source, toOffset: destination)
        WorkoutSection.resequence(sections)
        workout.markDirty()
        try context.save()
    }

    /// Creates a standalone template section (`workout == nil`) — reachable from the
    /// Section Templates screen's "+" button, not from any workout. Never locked, so
    /// no guard needed.
    static func createTemplate(name: String, type: WorkoutSectionType, description: String? = nil, context: ModelContext) -> WorkoutSection {
        let section = WorkoutSection(workout: nil, sortOrder: 0, sectionType: type, name: name, description: description)
        context.insert(section)
        if type == .time {
            let getReady = TimeSectionStep(section: section, sortOrder: 0, stepType: .getReady, exercise: nil, durationSeconds: 15)
            context.insert(getReady)
        }
        try? context.save()
        return section
    }

    /// Renames a section — in-workout or template alike. The name field is what
    /// distinguishes one section from another once several of the same type exist.
    /// `nil` clears the name back to its type-based fallback label.
    static func rename(_ section: WorkoutSection, to name: String?, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.name = name
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// Sets a template's description — shown in the templates list and the "Import
    /// Template" picker. Templates are never locked, so no guard needed.
    static func updateDescription(_ section: WorkoutSection, to description: String?, context: ModelContext) throws {
        section.sectionDescription = description
        section.markDirty()
        try context.save()
    }

    // MARK: - Time steps

    @discardableResult
    static func addTimeStep(to section: WorkoutSection, stepType: TimeStepType, exercise: Exercise?, durationSeconds: Int, context: ModelContext) throws -> TimeSectionStep {
        let workout = try requireUnlockedParent(of: section, context: context)
        let nextOrder = (section.timeSteps.map(\.sortOrder).max() ?? -1) + 1
        let step = TimeSectionStep(section: section, sortOrder: nextOrder, stepType: stepType, exercise: exercise, durationSeconds: durationSeconds)
        context.insert(step)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return step
    }

    static func deleteTimeStep(_ step: TimeSectionStep, from section: WorkoutSection, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        SyncDeletion.delete(step, context: context)
        TimeSectionStep.resequence(section.sortedTimeSteps.filter { $0.id != step.id })
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func moveTimeSteps(in section: WorkoutSection, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        var steps = section.sortedTimeSteps
        steps.move(fromOffsets: source, toOffset: destination)
        TimeSectionStep.resequence(steps)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// Inserts a rest step immediately after `step` — the per-row "+ Rest" action.
    /// Only one rest is meaningful directly after a given exercise; the caller is
    /// responsible for disabling the affordance once one already follows.
    @discardableResult
    static func addRestStep(after step: TimeSectionStep, durationSeconds: Int, context: ModelContext) throws -> TimeSectionStep {
        guard let section = step.section else { throw WorkoutEditingError.locked }
        let workout = try requireUnlockedParent(of: section, context: context)
        var steps = section.sortedTimeSteps
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { throw WorkoutEditingError.locked }

        let rest = TimeSectionStep(section: section, sortOrder: 0, stepType: .rest, exercise: nil, durationSeconds: durationSeconds)
        context.insert(rest)
        steps.insert(rest, at: index + 1)
        TimeSectionStep.resequence(steps)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return rest
    }

    // MARK: - Rep exercises

    @discardableResult
    static func addRepExercise(to section: WorkoutSection, exercise: Exercise, targetSets: Int, customRestSeconds: Int?, trackingMode: RepExerciseTrackingMode = .repsWeight, headStartSeconds: Int = 3, allowsBodyweight: Bool = false, tracksSides: Bool = false, preferredEquipment: Equipment? = nil, prefersBodyweight: Bool = false, context: ModelContext) throws -> RepSectionExercise {
        let workout = try requireUnlockedParent(of: section, context: context)
        let nextOrder = (section.repExercises.map(\.sortOrder).max() ?? -1) + 1
        let entry = RepSectionExercise(section: section, sortOrder: nextOrder, exercise: exercise, targetSets: targetSets, customRestSeconds: customRestSeconds, trackingMode: trackingMode, headStartSeconds: headStartSeconds, allowsBodyweight: allowsBodyweight, tracksSides: tracksSides, preferredEquipment: preferredEquipment, prefersBodyweight: prefersBodyweight)
        context.insert(entry)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return entry
    }

    static func deleteRepExercise(_ entry: RepSectionExercise, from section: WorkoutSection, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        SyncDeletion.delete(entry, context: context)
        RepSectionExercise.resequence(section.sortedRepExercises.filter { $0.id != entry.id })
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func moveRepExercises(in section: WorkoutSection, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        var entries = section.sortedRepExercises
        entries.move(fromOffsets: source, toOffset: destination)
        RepSectionExercise.resequence(entries)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    // MARK: - Quick exercises (EMOM/AMRAP)

    @discardableResult
    static func addQuickExercise(to section: WorkoutSection, exercise: Exercise, context: ModelContext) throws -> SectionExerciseEntry {
        let workout = try requireUnlockedParent(of: section, context: context)
        let nextOrder = (section.quickExercises.map(\.sortOrder).max() ?? -1) + 1
        let entry = SectionExerciseEntry(section: section, sortOrder: nextOrder, exercise: exercise)
        context.insert(entry)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return entry
    }

    static func deleteQuickExercise(_ entry: SectionExerciseEntry, from section: WorkoutSection, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        SyncDeletion.delete(entry, context: context)
        SectionExerciseEntry.resequence(section.sortedQuickExercises.filter { $0.id != entry.id })
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func moveQuickExercises(in section: WorkoutSection, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        var entries = section.sortedQuickExercises
        entries.move(fromOffsets: source, toOffset: destination)
        SectionExerciseEntry.resequence(entries)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// EMOM only: number of 1-minute rounds.
    static func updateEmomRoundCount(_ section: WorkoutSection, to count: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.emomRoundCount = count
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// EMOM only: run rounds open-ended until the user stops it, instead of to a count.
    ///
    /// Clamps `repeatCount` as it goes — an open-ended section has no end for a second
    /// pass to start after, and a stored repeat left behind would reappear the moment
    /// to-failure was switched back off.
    static func updateEmomToFailure(_ section: WorkoutSection, to toFailure: Bool, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.emomToFailure = toFailure
        if toFailure {
            section.repeatCount = 1
            section.sectionRestSeconds = 0
        }
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// EMOM/AMRAP only: whether this section's round count is a personal record.
    ///
    /// Mints the record identity on first enable and never re-mints it, so a section that
    /// is switched off before it has ever been done rejoins its own record rather than
    /// starting a second one.
    ///
    /// Once a record *has* been set, this is a one-way door: `requireUnlockedParent`
    /// refuses the change like any other, in a workout and on a template alike. The
    /// record is the reason the section can't be edited, so a toggle that removed it
    /// would be an unlock button for the very thing the lock protects.
    static func updateTracksRecord(_ section: WorkoutSection, to tracks: Bool, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        // A fixed-round EMOM has no record worth keeping — every completed run ties at
        // the round count. Ignored rather than thrown: the UI already prevents this, and
        // the one other caller is the seed importer, whose whole contract is to skip
        // settings it can't apply rather than abort the import over one section.
        guard !tracks || section.canTrackRecord else { return }
        section.tracksRecord = tracks
        if tracks {
            if section.recordGroupID == nil {
                section.recordGroupID = UUID()
            }
            // Locks immediately when the identity it rejoins already has a record — the
            // case where a section was switched off before ever being done, then back on
            // after a copy of it set the record. Without this the stored stamp and
            // `hasFiledRecord` disagree: the card would show its edit actions while every
            // one of them threw.
            if section.recordLockedAt == nil, hasFiledRecord(section, context: context) {
                section.recordLockedAt = .now
            }
        }
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// AMRAP only: total countdown duration, in seconds.
    static func updateAmrapDuration(_ section: WorkoutSection, to seconds: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.amrapDurationSeconds = seconds
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// Time/EMOM/AMRAP only: whether the section's timer starts automatically.
    static func updateAutostart(_ section: WorkoutSection, to autostart: Bool, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.autostart = autostart
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// How many times the whole section runs back to back. Any type.
    static func updateRepeatCount(_ section: WorkoutSection, to count: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.repeatCount = max(1, count)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// Whether the count-in plays before every pass or only the first. Any timed type.
    static func updateRepeatsGetReady(_ section: WorkoutSection, to repeats: Bool, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.repeatsGetReadyEachPass = repeats
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// The breather between passes. Any timed type; `0` means none.
    static func updateSectionRest(_ section: WorkoutSection, to seconds: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section, context: context)
        section.sectionRestSeconds = max(0, seconds)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    // MARK: - Guards

    private static func requireUnlocked(_ workout: Workout) throws {
        guard !workout.isLocked else { throw WorkoutEditingError.locked }
    }

    /// `nil` return means `section` is a template (no parent workout) — nothing to mark
    /// dirty at the workout level. A template is *not* automatically editable: one that
    /// tracks a record locks like a workout once a result has been filed against it.
    ///
    /// The live-record check is what makes that lock authoritative. `section.isLocked`
    /// reads a stored stamp, which a copy carrying the same `recordGroupID` can be
    /// missing — a section imported from a share, or one copied out before the first
    /// result was ever recorded. Those copies feed the same record, so they have to be
    /// refused too.
    @discardableResult
    static func requireUnlockedParent(of section: WorkoutSection, context: ModelContext) throws -> Workout? {
        // The record lock is checked first so its more specific message wins for a
        // tracked section that also sits in a used workout.
        if section.tracksRecord, section.recordLockedAt != nil || hasFiledRecord(section, context: context) {
            throw WorkoutEditingError.recordLocked
        }
        guard !section.isLocked else { throw WorkoutEditingError.locked }
        return section.workout
    }

    /// Whether a result has ever been filed against this section's record. Short-circuits
    /// before the fetch for the overwhelming majority of sections, which track nothing.
    static func hasFiledRecord(_ section: WorkoutSection, context: ModelContext) -> Bool {
        guard section.tracksRecord, let groupID = section.recordGroupID else { return false }
        return PersonalRecordQueries.sectionRecord(groupID: groupID, context: context) != nil
    }
}
