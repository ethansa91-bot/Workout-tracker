import Foundation
import SwiftData

/// Deep-copies a locked workout into a brand new, unlocked one — the only sanctioned
/// way to edit a workout that a session has already used. Catalog references
/// (`Exercise`/`Equipment`) are shared with the original, not duplicated; only the
/// workout's own structural entities (blocks, steps, rep exercises) get fresh rows.
enum WorkoutCloningService {
    static func clone(_ original: Workout, context: ModelContext) -> Workout {
        let copy = Workout(name: "\(original.name) Copy", notes: original.notes, clonedFromWorkoutId: original.id, kind: original.kind)
        context.insert(copy)
        // Workouts list is sorted newest-first; backdating the copy just before the
        // original makes it sort directly underneath instead of at the very top.
        copy.createdAt = original.createdAt.addingTimeInterval(-0.001)

        for block in original.sortedBlocks {
            let blockCopy = WorkoutBlock(workout: copy, sortOrder: block.sortOrder, blockType: block.blockType, name: block.name)
            context.insert(blockCopy)

            for step in block.sortedTimeSteps {
                let stepCopy = TimeBlockStep(
                    block: blockCopy,
                    sortOrder: step.sortOrder,
                    stepType: step.stepType,
                    exercise: step.exercise,
                    durationSeconds: step.durationSeconds
                )
                context.insert(stepCopy)
            }

            for entry in block.sortedRepExercises {
                let entryCopy = RepBlockExercise(
                    block: blockCopy,
                    sortOrder: entry.sortOrder,
                    exercise: entry.exercise,
                    targetSets: entry.targetSets,
                    customRestSeconds: entry.customRestSeconds
                )
                context.insert(entryCopy)
            }
        }

        try? context.save()
        return copy
    }
}
