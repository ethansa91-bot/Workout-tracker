import Foundation

enum WorkoutEditDestination: Hashable, Identifiable {
    case workout(Workout)
    case section(WorkoutSection)

    var id: UUID {
        switch self {
        case .workout(let workout): return workout.id
        case .section(let section): return section.id
        }
    }
}
