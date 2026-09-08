import Foundation
import SwiftData

/// Deep-copies a locked workout into a brand new, unlocked one — the only sanctioned
/// way to edit a workout that a session has already used. Catalog references
/// (`Exercise`/`Equipment`) are shared with the original, not duplicated; only the
/// workout's own structural entities (sections, steps, rep exercises) get fresh rows.
enum WorkoutCloningService {
    static func clone(_ original: Workout, context: ModelContext) -> Workout {
        let copy = Workout(name: "\(original.name) Copy", notes: original.notes, clonedFromWorkoutId: original.id)
        context.insert(copy)
        // Workouts list is sorted newest-first; backdating the copy just before the
        // original makes it sort directly underneath instead of at the very top.
        copy.createdAt = original.createdAt.addingTimeInterval(-0.001)
        // Carried over deliberately: "Clone & Edit" is the escape hatch from a locked
        // workout, and arriving in an untagged copy would drop it out of every filter the
        // original was findable through.
        copy.tags = original.sortedTags

        deepCopySections(from: original, into: copy, context: context)
        try? context.save()
        return copy
    }

    /// The "Edit" escape hatch for a locked workout, alongside `clone`'s "Clone & Edit".
    /// Builds the same kind of independent structural copy, but keeps the original's
    /// exact name — this isn't meant to read as a separate workout — and links the two
    /// through `versionGroupID` so the original becomes a queryable past version instead
    /// of an unrelated duplicate. Also repoints any not-yet-performed scheduled
    /// occurrences onto the new version, so the next time this workout comes up it's
    /// the updated one.
    static func createNewVersion(of original: Workout, context: ModelContext) -> Workout {
        let groupID = original.versionGroupID ?? UUID()
        original.versionGroupID = groupID
        original.isSupersededVersion = true
        original.markDirty()

        let copy = Workout(name: original.name, notes: original.notes, clonedFromWorkoutId: original.id)
        context.insert(copy)
        copy.createdAt = original.createdAt.addingTimeInterval(-0.001)
        copy.tags = original.sortedTags
        copy.versionGroupID = groupID

        deepCopySections(from: original, into: copy, context: context)
        ScheduledWorkoutService.repointFutureSchedules(from: original, to: copy, context: context)
        try? context.save()
        return copy
    }

    private static func deepCopySections(from original: Workout, into copy: Workout, context: ModelContext) {
        for section in original.sortedSections {
            let sectionCopy = WorkoutSection(workout: copy, sortOrder: section.sortOrder, sectionType: section.sectionType, name: section.name)
            sectionCopy.emomRoundCount = section.emomRoundCount
            sectionCopy.amrapDurationSeconds = section.amrapDurationSeconds
            sectionCopy.getReadySeconds = section.getReadySeconds
            sectionCopy.repeatsGetReadyEachPass = section.repeatsGetReadyEachPass
            sectionCopy.sectionRestSeconds = section.sectionRestSeconds
            sectionCopy.autostart = section.autostart
            sectionCopy.repeatCount = section.repeatCount
            sectionCopy.emomToFailure = section.emomToFailure
            // Carried, not re-minted: a "Clone & Edit" of a locked workout keeps
            // pointing at the same record, so the benchmark's history follows the copy
            // the user actually goes on to use. See `WorkoutSectionCloningService`.
            sectionCopy.tracksRecord = section.tracksRecord
            sectionCopy.recordGroupID = section.recordGroupID
            sectionCopy.recordLockedAt = section.recordLockedAt
            context.insert(sectionCopy)

            for entry in section.sortedQuickExercises {
                let entryCopy = SectionExerciseEntry(section: sectionCopy, sortOrder: entry.sortOrder, exercise: entry.exercise, executionType: entry.executionType, targetReps: entry.targetReps)
                entryCopy.sideRaw = entry.sideRaw
                context.insert(entryCopy)
            }

            for step in section.sortedTimeSteps {
                let stepCopy = TimeSectionStep(
                    section: sectionCopy,
                    sortOrder: step.sortOrder,
                    stepType: step.stepType,
                    exercise: step.exercise,
                    durationSeconds: step.durationSeconds
                )
                stepCopy.color = step.color
                stepCopy.executionType = step.executionType
                stepCopy.sideRaw = step.sideRaw
                stepCopy.startingWeight = step.startingWeight
                context.insert(stepCopy)
            }

            for entry in section.sortedRepExercises {
                let entryCopy = RepSectionExercise(
                    section: sectionCopy,
                    sortOrder: entry.sortOrder,
                    exercise: entry.exercise,
                    targetSets: entry.targetSets,
                    customRestSeconds: entry.customRestSeconds,
                    trackingMode: entry.trackingMode,
                    headStartSeconds: entry.headStartSeconds,
                    allowsBodyweight: entry.allowsBodyweight,
                    tracksSides: entry.tracksSides,
                    preferredEquipment: entry.preferredEquipment,
                    prefersBodyweight: entry.prefersBodyweight,
                    executionType: entry.executionType,
                    progressionEnabled: entry.progressionEnabled
                )
                entryCopy.startingWeight = entry.startingWeight
                entryCopy.startingReps = entry.startingReps
                context.insert(entryCopy)
            }
        }
    }
}
