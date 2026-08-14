import Foundation
import SwiftData

enum WorkoutBlockType: String, Codable {
    case time, rep
}

@Model
final class WorkoutBlock: SyncableModel, Orderable {
    @Attribute(.unique) var id: UUID
    var workout: Workout?
    var sortOrder: Int
    var name: String?
    var blockTypeRaw: String
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    /// Populated only when `blockType == .time`.
    @Relationship(deleteRule: .cascade, inverse: \TimeBlockStep.block)
    var timeSteps: [TimeBlockStep] = []

    /// Populated only when `blockType == .rep`.
    @Relationship(deleteRule: .cascade, inverse: \RepBlockExercise.block)
    var repExercises: [RepBlockExercise] = []

    var blockType: WorkoutBlockType {
        get { WorkoutBlockType(rawValue: blockTypeRaw) ?? .time }
        set { blockTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), workout: Workout? = nil, sortOrder: Int, blockType: WorkoutBlockType, name: String? = nil) {
        self.id = id
        self.workout = workout
        self.sortOrder = sortOrder
        self.blockTypeRaw = blockType.rawValue
        self.name = name
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }

    var sortedTimeSteps: [TimeBlockStep] {
        timeSteps.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedRepExercises: [RepBlockExercise] {
        repExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }
}
