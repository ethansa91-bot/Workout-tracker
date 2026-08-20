import Foundation
import SwiftData

@Model
final class Muscle: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    var iconSymbolName: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The `@Relationship(inverse:)` annotation for this pair lives on `MuscleCategory`.
    var categoriesStorage: [MuscleCategory]?
    var categories: [MuscleCategory] {
        get { categoriesStorage ?? [] }
        set { categoriesStorage = newValue }
    }

    /// The `@Relationship(inverse:)` annotation for this pair lives on `Exercise`.
    var exercisesStorage: [Exercise]?
    var exercises: [Exercise] {
        get { exercisesStorage ?? [] }
        set { exercisesStorage = newValue }
    }

    init(id: UUID = UUID(), name: String, iconSymbolName: String) {
        self.id = id
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
