import Foundation
import SwiftData

/// Deep-copies a locked workout into a brand new, unlocked one — the only sanctioned
/// way to edit a workout that a session has already used. Catalog references
/// (`Exercise`/`Equipment`) are shared with the original, not duplicated; only the
/// workout's own structural entities (sections, steps, rep exercises) get fresh rows.
enum WorkoutCloningService {
    static func clone(_ original: Workout, context: ModelContext) -> Workout {
        let copy = Workout(name: "\(original.name) Copy", notes: original.notes, clonedFromWorkoutId: original.id, kind: original.kind)
        context.insert(copy)
        // Workouts list is sorted newest-first; backdating the copy just before the
        // original makes it sort directly underneath instead of at the very top.
        copy.createdAt = original.createdAt.addingTimeInterval(-0.001)

        for section in original.sortedSections {
            let sectionCopy = WorkoutSection(workout: copy, sortOrder: section.sortOrder, sectionType: section.sectionType, name: section.name)
            sectionCopy.emomRoundCount = section.emomRoundCount
            sectionCopy.amrapDurationSeconds = section.amrapDurationSeconds
            context.insert(sectionCopy)

            for entry in section.sortedQuickExercises {
                let entryCopy = SectionExerciseEntry(section: sectionCopy, sortOrder: entry.sortOrder, exercise: entry.exercise)
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
                    headStartSeconds: entry.headStartSeconds
                )
                context.insert(entryCopy)
            }
        }

        try? context.save()
        return copy
    }
}
