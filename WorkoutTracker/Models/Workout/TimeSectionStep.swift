import Foundation
import SwiftData

enum TimeStepType: String, Codable {
    case exercise, rest, getReady
}

/// One entry in a time block's sequence: either an exercise held for a duration, or a
/// rest. From a UI/runtime perspective a rest behaves exactly like an exercise step
/// (it has a duration and advances the same way) except it has no picture.
@Model
final class TimeBlockStep: SyncableModel, Orderable {
    @Attribute(.unique) var id: UUID
    var block: WorkoutBlock?
    var sortOrder: Int
    var stepTypeRaw: String
    /// nil for rest steps.
    var exercise: Exercise?
    var durationSeconds: Int
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    var stepType: TimeStepType {
        get { TimeStepType(rawValue: stepTypeRaw) ?? .exercise }
        set { stepTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), block: WorkoutBlock? = nil, sortOrder: Int, stepType: TimeStepType, exercise: Exercise? = nil, durationSeconds: Int) {
        self.id = id
        self.block = block
        self.sortOrder = sortOrder
        self.stepTypeRaw = stepType.rawValue
        self.exercise = exercise
        self.durationSeconds = durationSeconds
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
