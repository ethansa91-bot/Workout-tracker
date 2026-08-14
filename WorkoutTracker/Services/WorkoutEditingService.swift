import Foundation
import SwiftData
import SwiftUI

enum WorkoutEditingError: LocalizedError {
    case locked

    var errorDescription: String? {
        switch self {
        case .locked:
            return "This workout has already been used in a session and can no longer be edited. Clone it to make changes."
        }
    }
}

/// Every mutation to a workout's structure goes through here, not directly through
/// SwiftData — the one thing every entry point has in common is checking
/// `workout.isLocked` first. SwiftData itself has no way to enforce that.
enum WorkoutEditingService {
    static func createWorkout(name: String, kind: WorkoutKind = .personalized, context: ModelContext) -> Workout {
        let workout = Workout(name: name, kind: kind)
        context.insert(workout)
        try? context.save()
        return workout
    }

    static func rename(_ workout: Workout, to name: String, context: ModelContext) throws {
        try requireUnlocked(workout)
        workout.name = name
        workout.markDirty()
        try context.save()
    }

    static func updateNotes(_ workout: Workout, to notes: String?, context: ModelContext) throws {
        try requireUnlocked(workout)
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
        let workout = try requireUnlockedParent(of: section)
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
        let workout = try requireUnlockedParent(of: section)
        let nextOrder = (section.timeSteps.map(\.sortOrder).max() ?? -1) + 1
        let step = TimeSectionStep(section: section, sortOrder: nextOrder, stepType: stepType, exercise: exercise, durationSeconds: durationSeconds)
        context.insert(step)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return step
    }

    static func deleteTimeStep(_ step: TimeSectionStep, from section: WorkoutSection, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        SyncDeletion.delete(step, context: context)
        TimeSectionStep.resequence(section.sortedTimeSteps.filter { $0.id != step.id })
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func moveTimeSteps(in section: WorkoutSection, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
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
        let workout = try requireUnlockedParent(of: section)
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
    static func addRepExercise(to section: WorkoutSection, exercise: Exercise, targetSets: Int, customRestSeconds: Int?, trackingMode: RepExerciseTrackingMode = .repsWeight, headStartSeconds: Int = 3, context: ModelContext) throws -> RepSectionExercise {
        let workout = try requireUnlockedParent(of: section)
        let nextOrder = (section.repExercises.map(\.sortOrder).max() ?? -1) + 1
        let entry = RepSectionExercise(section: section, sortOrder: nextOrder, exercise: exercise, targetSets: targetSets, customRestSeconds: customRestSeconds, trackingMode: trackingMode, headStartSeconds: headStartSeconds)
        context.insert(entry)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return entry
    }

    static func deleteRepExercise(_ entry: RepSectionExercise, from section: WorkoutSection, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        SyncDeletion.delete(entry, context: context)
        RepSectionExercise.resequence(section.sortedRepExercises.filter { $0.id != entry.id })
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func moveRepExercises(in section: WorkoutSection, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
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
        let workout = try requireUnlockedParent(of: section)
        let nextOrder = (section.quickExercises.map(\.sortOrder).max() ?? -1) + 1
        let entry = SectionExerciseEntry(section: section, sortOrder: nextOrder, exercise: exercise)
        context.insert(entry)
        section.markDirty()
        workout?.markDirty()
        try context.save()
        return entry
    }

    static func deleteQuickExercise(_ entry: SectionExerciseEntry, from section: WorkoutSection, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        SyncDeletion.delete(entry, context: context)
        SectionExerciseEntry.resequence(section.sortedQuickExercises.filter { $0.id != entry.id })
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func moveQuickExercises(in section: WorkoutSection, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        var entries = section.sortedQuickExercises
        entries.move(fromOffsets: source, toOffset: destination)
        SectionExerciseEntry.resequence(entries)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// EMOM only: number of 1-minute rounds.
    static func updateEmomRoundCount(_ section: WorkoutSection, to count: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        section.emomRoundCount = count
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// AMRAP only: total countdown duration, in seconds.
    static func updateAmrapDuration(_ section: WorkoutSection, to seconds: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        section.amrapDurationSeconds = seconds
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    // MARK: - Guards

    private static func requireUnlocked(_ workout: Workout) throws {
        guard !workout.isLocked else { throw WorkoutEditingError.locked }
    }

    /// `nil` return means `section` is a template (no parent workout) — always
    /// editable, nothing to mark dirty at the workout level.
    @discardableResult
    static func requireUnlockedParent(of section: WorkoutSection) throws -> Workout? {
        guard !section.isLocked else { throw WorkoutEditingError.locked }
        return section.workout
    }
}
