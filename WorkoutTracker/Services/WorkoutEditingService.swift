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

    // MARK: - Blocks

    static func addBlock(to workout: Workout, type: WorkoutBlockType, context: ModelContext) throws -> WorkoutBlock {
        try requireUnlocked(workout)
        let nextOrder = (workout.blocks.map(\.sortOrder).max() ?? -1) + 1
        let block = WorkoutBlock(workout: workout, sortOrder: nextOrder, blockType: type)
        context.insert(block)
        if type == .time {
            let getReady = TimeBlockStep(block: block, sortOrder: 0, stepType: .getReady, exercise: nil, durationSeconds: 15)
            context.insert(getReady)
        }
        workout.markDirty()
        try context.save()
        return block
    }

    static func deleteBlock(_ block: WorkoutBlock, from workout: Workout, context: ModelContext) throws {
        try requireUnlocked(workout)
        SyncDeletion.delete(block, context: context)
        WorkoutBlock.resequence(workout.sortedBlocks.filter { $0.id != block.id })
        workout.markDirty()
        try context.save()
    }

    static func moveBlocks(in workout: Workout, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        try requireUnlocked(workout)
        var blocks = workout.sortedBlocks
        blocks.move(fromOffsets: source, toOffset: destination)
        WorkoutBlock.resequence(blocks)
        workout.markDirty()
        try context.save()
    }

    // MARK: - Time steps

    @discardableResult
    static func addTimeStep(to block: WorkoutBlock, stepType: TimeStepType, exercise: Exercise?, durationSeconds: Int, context: ModelContext) throws -> TimeBlockStep {
        let workout = try requireUnlockedParent(of: block)
        let nextOrder = (block.timeSteps.map(\.sortOrder).max() ?? -1) + 1
        let step = TimeBlockStep(block: block, sortOrder: nextOrder, stepType: stepType, exercise: exercise, durationSeconds: durationSeconds)
        context.insert(step)
        block.markDirty()
        workout.markDirty()
        try context.save()
        return step
    }

    static func deleteTimeStep(_ step: TimeBlockStep, from block: WorkoutBlock, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: block)
        SyncDeletion.delete(step, context: context)
        TimeBlockStep.resequence(block.sortedTimeSteps.filter { $0.id != step.id })
        block.markDirty()
        workout.markDirty()
        try context.save()
    }

    static func moveTimeSteps(in block: WorkoutBlock, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: block)
        var steps = block.sortedTimeSteps
        steps.move(fromOffsets: source, toOffset: destination)
        TimeBlockStep.resequence(steps)
        block.markDirty()
        workout.markDirty()
        try context.save()
    }

    /// Inserts a rest step immediately after `step` — the per-row "+ Rest" action.
    /// Only one rest is meaningful directly after a given exercise; the caller is
    /// responsible for disabling the affordance once one already follows.
    @discardableResult
    static func addRestStep(after step: TimeBlockStep, durationSeconds: Int, context: ModelContext) throws -> TimeBlockStep {
        guard let block = step.block else { throw WorkoutEditingError.locked }
        let workout = try requireUnlockedParent(of: block)
        var steps = block.sortedTimeSteps
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { throw WorkoutEditingError.locked }

        let rest = TimeBlockStep(block: block, sortOrder: 0, stepType: .rest, exercise: nil, durationSeconds: durationSeconds)
        context.insert(rest)
        steps.insert(rest, at: index + 1)
        TimeBlockStep.resequence(steps)
        block.markDirty()
        workout.markDirty()
        try context.save()
        return rest
    }

    // MARK: - Rep exercises

    @discardableResult
    static func addRepExercise(to block: WorkoutBlock, exercise: Exercise, targetSets: Int, customRestSeconds: Int?, trackingMode: RepExerciseTrackingMode = .repsWeight, headStartSeconds: Int = 3, context: ModelContext) throws -> RepBlockExercise {
        let workout = try requireUnlockedParent(of: block)
        let nextOrder = (block.repExercises.map(\.sortOrder).max() ?? -1) + 1
        let entry = RepBlockExercise(block: block, sortOrder: nextOrder, exercise: exercise, targetSets: targetSets, customRestSeconds: customRestSeconds, trackingMode: trackingMode, headStartSeconds: headStartSeconds)
        context.insert(entry)
        block.markDirty()
        workout.markDirty()
        try context.save()
        return entry
    }

    static func deleteRepExercise(_ entry: RepBlockExercise, from block: WorkoutBlock, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: block)
        SyncDeletion.delete(entry, context: context)
        RepBlockExercise.resequence(block.sortedRepExercises.filter { $0.id != entry.id })
        block.markDirty()
        workout.markDirty()
        try context.save()
    }

    static func moveRepExercises(in block: WorkoutBlock, from source: IndexSet, to destination: Int, context: ModelContext) throws {
        let workout = try requireUnlockedParent(of: block)
        var entries = block.sortedRepExercises
        entries.move(fromOffsets: source, toOffset: destination)
        RepBlockExercise.resequence(entries)
        block.markDirty()
        workout.markDirty()
        try context.save()
    }

    // MARK: - Guards

    private static func requireUnlocked(_ workout: Workout) throws {
        guard !workout.isLocked else { throw WorkoutEditingError.locked }
    }

    @discardableResult
    private static func requireUnlockedParent(of block: WorkoutBlock) throws -> Workout {
        guard let workout = block.workout else { throw WorkoutEditingError.locked }
        try requireUnlocked(workout)
        return workout
    }
}
