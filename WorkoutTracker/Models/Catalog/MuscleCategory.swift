import Foundation
import SwiftData

/// A tag such as legs, upperBody, lowerBody, arms, core. Muscles carry many of these so
/// they can be searched/filtered from several angles at once.
@Model
final class MuscleCategory: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(inverse: \Muscle.categories)
    var muscles: [Muscle] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
