import Foundation
import SwiftData

/// "Selecting 5 exercises plus rest, clone, means I do all twice": duplicates a
/// contiguous run of steps/exercises within a section, appending the copies to the end
/// of the section.
enum WorkoutSectionCloningService {
    static func cloneTimeSteps(in section: WorkoutSection, range: Range<Int>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        var steps = section.sortedTimeSteps
        guard range.lowerBound >= 0, range.upperBound <= steps.count, !range.isEmpty else { return }

        let clones = steps[range].map { original -> TimeSectionStep in
            let clone = TimeSectionStep(section: section, sortOrder: 0, stepType: original.stepType, exercise: original.exercise, durationSeconds: original.durationSeconds)
            clone.color = original.color
            return clone
        }
        clones.forEach { context.insert($0) }
        steps.insert(contentsOf: clones, at: steps.count)
        TimeSectionStep.resequence(steps)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func cloneRepExercises(in section: WorkoutSection, range: Range<Int>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        var entries = section.sortedRepExercises
        guard range.lowerBound >= 0, range.upperBound <= entries.count, !range.isEmpty else { return }

        let clones = entries[range].map { original in
            RepSectionExercise(section: section, sortOrder: 0, exercise: original.exercise, targetSets: original.targetSets, customRestSeconds: original.customRestSeconds, trackingMode: original.trackingMode, headStartSeconds: original.headStartSeconds, allowsBodyweight: original.allowsBodyweight, tracksSides: original.tracksSides)
        }
        clones.forEach { context.insert($0) }
        entries.insert(contentsOf: clones, at: entries.count)
        RepSectionExercise.resequence(entries)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// Where a batch of copies belongs: immediately after the last row they came
    /// from, so a clone shows up next to what you cloned rather than at the far end of
    /// a long section. Copies keep their original relative order as one block.
    private static func insertIndex<T: Identifiable>(in items: [T], ids: Set<UUID>) -> Int where T.ID == UUID {
        guard let last = items.lastIndex(where: { ids.contains($0.id) }) else { return items.count }
        return last + 1
    }

    // MARK: - Cloning an arbitrary selection
    //
    // The range-based methods above back the section editors' multi-select, which only
    // enables Clone for an adjacent run, and append their copies to the end. The recap
    // page lets you tick any rows at all, so these take a set of ids instead — and put
    // the copies right after the last row they came from rather than at the end.

    static func cloneTimeSteps(in section: WorkoutSection, ids: Set<UUID>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        var steps = section.sortedTimeSteps
        let clones = steps.filter { ids.contains($0.id) }.map { original -> TimeSectionStep in
            let clone = TimeSectionStep(section: section, sortOrder: 0, stepType: original.stepType, exercise: original.exercise, durationSeconds: original.durationSeconds)
            clone.color = original.color
            return clone
        }
        guard !clones.isEmpty else { return }

        clones.forEach { context.insert($0) }
        steps.insert(contentsOf: clones, at: insertIndex(in: steps, ids: ids))
        TimeSectionStep.resequence(steps)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// `preferredEquipment` is deliberately not carried over — no clone path in this
    /// service copies it, so the copy falls back to the exercise's default the same way
    /// a range-clone or an imported template does.
    static func cloneRepExercises(in section: WorkoutSection, ids: Set<UUID>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        var entries = section.sortedRepExercises
        let clones = entries.filter { ids.contains($0.id) }.map { original in
            RepSectionExercise(section: section, sortOrder: 0, exercise: original.exercise, targetSets: original.targetSets, customRestSeconds: original.customRestSeconds, trackingMode: original.trackingMode, headStartSeconds: original.headStartSeconds, allowsBodyweight: original.allowsBodyweight, tracksSides: original.tracksSides)
        }
        guard !clones.isEmpty else { return }

        clones.forEach { context.insert($0) }
        entries.insert(contentsOf: clones, at: insertIndex(in: entries, ids: ids))
        RepSectionExercise.resequence(entries)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    static func cloneQuickExercises(in section: WorkoutSection, ids: Set<UUID>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: section)
        var entries = section.sortedQuickExercises
        let clones = entries.filter { ids.contains($0.id) }.map { original in
            SectionExerciseEntry(section: section, sortOrder: 0, exercise: original.exercise)
        }
        guard !clones.isEmpty else { return }

        clones.forEach { context.insert($0) }
        entries.insert(contentsOf: clones, at: insertIndex(in: entries, ids: ids))
        SectionExerciseEntry.resequence(entries)
        section.markDirty()
        workout?.markDirty()
        try context.save()
    }

    /// Duplicates a whole section — every step/exercise it contains — inserting the copy
    /// immediately after the original in the workout's section order.
    @discardableResult
    static func cloneSection(_ section: WorkoutSection, context: ModelContext) throws -> WorkoutSection {
        let workout = try requireUnlockedParent(of: section)
        guard let workout else { return section }
        var sections = workout.sortedSections
        guard let originalIndex = sections.firstIndex(where: { $0.id == section.id }) else { return section }

        let copy = makeSectionCopy(of: section, workout: workout, sortOrder: 0, name: section.name)
        context.insert(copy)
        copySteps(from: section, into: copy, context: context)

        sections.insert(copy, at: originalIndex + 1)
        WorkoutSection.resequence(sections)
        workout.markDirty()
        try context.save()
        return copy
    }

    /// Deep-copies `section` into a brand new orphan template (`workout == nil`),
    /// reusable from any other workout via `importTemplate`. No lock guard: copying a
    /// locked workout's section into a template is read-only, mirroring how
    /// `WorkoutCloningService.clone` already bypasses the source's lock.
    @discardableResult
    static func saveAsTemplate(_ section: WorkoutSection, name: String, context: ModelContext) throws -> WorkoutSection {
        let template = makeSectionCopy(of: section, workout: nil, sortOrder: 0, name: name)
        context.insert(template)
        copySteps(from: section, into: template, context: context)
        try context.save()
        return template
    }

    /// Deep-copies a template section into `workout`, appended to the end of its
    /// sections. Throws if `workout` is locked.
    @discardableResult
    static func importTemplate(_ template: WorkoutSection, into workout: Workout, context: ModelContext) throws -> WorkoutSection {
        guard !workout.isLocked else { throw WorkoutEditingError.locked }
        let nextOrder = (workout.sections.map(\.sortOrder).max() ?? -1) + 1
        let copy = makeSectionCopy(of: template, workout: workout, sortOrder: nextOrder, name: template.name)
        context.insert(copy)
        copySteps(from: template, into: copy, context: context)
        workout.markDirty()
        try context.save()
        return copy
    }

    /// A fresh `WorkoutSection` matching `source`'s type and EMOM/AMRAP settings —
    /// every clone/template/import path needs this same construction, just with a
    /// different destination workout/sortOrder/name.
    private static func makeSectionCopy(of source: WorkoutSection, workout: Workout?, sortOrder: Int, name: String?) -> WorkoutSection {
        let copy = WorkoutSection(workout: workout, sortOrder: sortOrder, sectionType: source.sectionType, name: name, description: source.sectionDescription)
        copy.emomRoundCount = source.emomRoundCount
        copy.amrapDurationSeconds = source.amrapDurationSeconds
        copy.autostart = source.autostart
        copy.repeatCount = source.repeatCount
        return copy
    }

    private static func copySteps(from source: WorkoutSection, into destination: WorkoutSection, context: ModelContext) {
        for step in source.sortedTimeSteps {
            let stepCopy = TimeSectionStep(
                section: destination,
                sortOrder: step.sortOrder,
                stepType: step.stepType,
                exercise: step.exercise,
                durationSeconds: step.durationSeconds
            )
            stepCopy.color = step.color
            context.insert(stepCopy)
        }
        for entry in source.sortedRepExercises {
            let entryCopy = RepSectionExercise(
                section: destination,
                sortOrder: entry.sortOrder,
                exercise: entry.exercise,
                targetSets: entry.targetSets,
                customRestSeconds: entry.customRestSeconds,
                trackingMode: entry.trackingMode,
                headStartSeconds: entry.headStartSeconds,
                allowsBodyweight: entry.allowsBodyweight,
                tracksSides: entry.tracksSides
            )
            context.insert(entryCopy)
        }
        for entry in source.sortedQuickExercises {
            let entryCopy = SectionExerciseEntry(section: destination, sortOrder: entry.sortOrder, exercise: entry.exercise)
            context.insert(entryCopy)
        }
    }

    @discardableResult
    private static func requireUnlockedParent(of section: WorkoutSection) throws -> Workout? {
        guard !section.isLocked else { throw WorkoutEditingError.locked }
        return section.workout
    }
}
