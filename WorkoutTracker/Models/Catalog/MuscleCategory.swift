import Foundation
import SwiftData

/// A tag such as legs, upperBody, lowerBody, arms, core. Muscles carry many of these so
/// they can be searched/filtered from several angles at once.
@Model
final class MuscleCategory: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    @Relationship(inverse: \Muscle.categoriesStorage)
    var musclesStorage: [Muscle]?
    var muscles: [Muscle] {
        get { musclesStorage ?? [] }
        set { musclesStorage = newValue }
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
