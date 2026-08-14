import Foundation
import SwiftData

@Model
final class Equipment: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconSymbolName: String
    /// True for equipment the user created themselves, vs. seeded catalog equipment.
    var isCustom: Bool
    /// Deprecated — replaced by `isAtHome`/`isAtGym`. Kept only so
    /// `EquipmentHomeGymMigration` can read its old value once; nothing else
    /// reads or writes it anymore.
    var isFavorited: Bool
    var isAtHome: Bool = false
    var isAtGym: Bool = false
    /// On = variable-weight equipment (dumbbells, vests) that exposes weight-unit and
    /// available-weight settings. Off = passive equipment (mats, benches) needed to
    /// perform an exercise but with no adjustable weight of its own.
    var isWeighted: Bool = false
    /// nil = use the global `AppSettings.weightUnit` default.
    var preferredWeightUnit: String?
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WeightCombo.equipment)
    var weightCombos: [WeightCombo] = []

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbolName: String,
        isCustom: Bool = false,
        isAtHome: Bool = false,
        isAtGym: Bool = false,
        isWeighted: Bool = false,
        preferredWeightUnit: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSymbolName = iconSymbolName
        self.isCustom = isCustom
        self.isFavorited = false
        self.isAtHome = isAtHome
        self.isAtGym = isAtGym
        self.isWeighted = isWeighted
        self.preferredWeightUnit = preferredWeightUnit
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

    var effectiveWeightUnit: String {
        preferredWeightUnit ?? AppSettings.weightUnit
    }
}
