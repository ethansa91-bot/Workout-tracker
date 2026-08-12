import Foundation
import SwiftData

@Model
final class RepBlockExercise: SyncableModel, Orderable {
    @Attribute(.unique) var id: UUID
    var block: WorkoutBlock?
    var sortOrder: Int
    var exercise: Exercise?
    var targetSets: Int
    /// nil falls back to `AppSettings.defaultRestSeconds`.
    var customRestSeconds: Int?
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    init(id: UUID = UUID(), block: WorkoutBlock? = nil, sortOrder: Int, exercise: Exercise? = nil, targetSets: Int, customRestSeconds: Int? = nil) {
        self.id = id
        self.block = block
        self.sortOrder = sortOrder
        self.exercise = exercise
        self.targetSets = targetSets
        self.customRestSeconds = customRestSeconds
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
