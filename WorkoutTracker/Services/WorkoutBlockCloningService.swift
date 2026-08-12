import Foundation
import SwiftData

/// "Selecting 5 exercises plus rest, clone, means I do all twice": duplicates a
/// contiguous run of steps/exercises within a block, appending the copies to the end
/// of the block.
enum WorkoutBlockCloningService {
    static func cloneTimeSteps(in block: WorkoutBlock, range: Range<Int>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: block)
        var steps = block.sortedTimeSteps
        guard range.lowerBound >= 0, range.upperBound <= steps.count, !range.isEmpty else { return }

        let clones = steps[range].map { original in
            TimeBlockStep(block: block, sortOrder: 0, stepType: original.stepType, exercise: original.exercise, durationSeconds: original.durationSeconds)
        }
        clones.forEach { context.insert($0) }
        steps.insert(contentsOf: clones, at: steps.count)
        TimeBlockStep.resequence(steps)
        block.markDirty()
        workout.markDirty()
        try context.save()
    }

    static func cloneRepExercises(in block: WorkoutBlock, range: Range<Int>, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: block)
        var entries = block.sortedRepExercises
        guard range.lowerBound >= 0, range.upperBound <= entries.count, !range.isEmpty else { return }

        let clones = entries[range].map { original in
            RepBlockExercise(block: block, sortOrder: 0, exercise: original.exercise, targetSets: original.targetSets, customRestSeconds: original.customRestSeconds)
        }
        clones.forEach { context.insert($0) }
        entries.insert(contentsOf: clones, at: entries.count)
        RepBlockExercise.resequence(entries)
        block.markDirty()
        workout.markDirty()
        try context.save()
    }

    /// Duplicates a whole block — every step/exercise it contains — inserting the copy
    /// immediately after the original in the workout's block order.
    @discardableResult
    static func cloneBlock(_ block: WorkoutBlock, context: ModelContext) throws -> WorkoutBlock {
        let workout = try requireUnlockedParent(of: block)
        var blocks = workout.sortedBlocks
        guard let originalIndex = blocks.firstIndex(where: { $0.id == block.id }) else { return block }

        let copy = WorkoutBlock(workout: workout, sortOrder: 0, blockType: block.blockType, name: block.name)
        context.insert(copy)

        for step in block.sortedTimeSteps {
            let stepCopy = TimeBlockStep(
                block: copy,
                sortOrder: step.sortOrder,
                stepType: step.stepType,
                exercise: step.exercise,
                durationSeconds: step.durationSeconds
            )
            context.insert(stepCopy)
        }
        for entry in block.sortedRepExercises {
            let entryCopy = RepBlockExercise(
                block: copy,
                sortOrder: entry.sortOrder,
                exercise: entry.exercise,
                targetSets: entry.targetSets,
                customRestSeconds: entry.customRestSeconds
            )
            context.insert(entryCopy)
        }

        blocks.insert(copy, at: originalIndex + 1)
        WorkoutBlock.resequence(blocks)
        workout.markDirty()
        try context.save()
        return copy
    }

    @discardableResult
    private static func requireUnlockedParent(of block: WorkoutBlock) throws -> Workout {
        guard let workout = block.workout, !workout.isLocked else { throw WorkoutEditingError.locked }
        return workout
    }
}
