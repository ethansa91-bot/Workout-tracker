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
}
