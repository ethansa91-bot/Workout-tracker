import Foundation
import SwiftData

/// calisthenics, strength, mobility, plyo, cardio, warmups, physio, ...
@Model
final class ExerciseCategory: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    @Relationship(inverse: \Exercise.categoriesStorage)
    var exercisesStorage: [Exercise]?
    var exercises: [Exercise] {
        get { exercisesStorage ?? [] }
        set { exercisesStorage = newValue }
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
