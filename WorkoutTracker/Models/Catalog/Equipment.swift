import Foundation
import SwiftData

@Model
final class Equipment: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconSymbolName: String
    /// True for equipment the user created themselves, vs. seeded catalog equipment.
    var isCustom: Bool
    /// "In my gym" — favoriting a catalog item, or auto-set when the item is custom-created.
    var isFavorited: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WeightCombo.equipment)
    var weightCombos: [WeightCombo] = []

    init(id: UUID = UUID(), name: String, iconSymbolName: String, isCustom: Bool = false, isFavorited: Bool = false) {
        self.id = id
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.isCustom = isCustom
        self.isFavorited = isFavorited || isCustom
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }

    var sortedWeightCombos: [WeightCombo] {
        weightCombos
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
