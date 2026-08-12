import Foundation
import SwiftData

/// calisthenics, strength, mobility, plyo, cardio, warmups, physio, ...
@Model
final class ExerciseCategory: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(inverse: \Exercise.categories)
    var exercises: [Exercise] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
