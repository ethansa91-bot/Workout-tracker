import Foundation
import SwiftData

@Model
final class Muscle: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconSymbolName: String
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    var categories: [MuscleCategory] = []

    @Relationship(inverse: \Exercise.muscles)
    var exercises: [Exercise] = []

    init(id: UUID = UUID(), name: String, iconSymbolName: String) {
        self.id = id
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
