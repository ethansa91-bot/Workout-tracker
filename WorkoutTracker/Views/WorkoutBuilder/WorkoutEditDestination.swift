import Foundation

enum WorkoutEditDestination: Hashable, Identifiable {
    case workout(Workout)
    case block(WorkoutBlock)

    var id: UUID {
        switch self {
        case .workout(let workout): return workout.id
        case .block(let block): return block.id
        }
    }

    /// By Time/By Reps workouts with an existing block jump straight to that block's
    /// exercise editor; Personalized (or a blockless single-kind workout) lands on
    /// the full workout editor.
    static func editing(_ workout: Workout) -> WorkoutEditDestination {
        if workout.kind != .personalized, let firstBlock = workout.sortedBlocks.first {
            return .block(firstBlock)
        }
        return .workout(workout)
    }
}
