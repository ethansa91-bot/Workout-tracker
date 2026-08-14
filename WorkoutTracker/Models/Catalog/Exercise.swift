import Foundation
import SwiftData

@Model
final class Exercise: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var label: String?
    var notes: String?
    var iconSymbolName: String
    /// Asset catalog name of a reference photo in `Assets.xcassets/ExercisePhotos`,
    /// when one was matched from free-exercise-db at seed/import time. nil falls back
    /// to `iconSymbolName` everywhere photos aren't shown.
    var imageAssetName: String?
    var isCustom: Bool
    var isFavorited: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    /// Deprecated — replaced by `equipmentItems`. Kept under its original name/type so
    /// SwiftData preserves existing on-disk data; a rename would make SwiftData treat it
    /// as an unrelated new relationship and silently drop everyone's existing link.
    /// Read once by `ExerciseEquipmentMigration`; nothing else reads or writes it anymore.
    var equipment: Equipment?
    /// Empty = bodyweight, no equipment needed. Can mix passive and weighted equipment.
    var equipmentItems: [Equipment] = []
    var muscles: [Muscle] = []
    var categories: [ExerciseCategory] = []

    /// The user's personal nickname when set, falling back to the catalog `name`.
    var displayName: String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : name
    }

    /// The weighted item among `equipmentItems`, if any — used to resolve weight
    /// options/unit. If more than one is attached, the first is used; logging weight
    /// against multiple simultaneous equipment per set isn't supported.
    var weightedEquipment: Equipment? {
        equipmentItems.first(where: \.isWeighted)
    }

    init(
        id: UUID = UUID(),
        name: String,
        label: String? = nil,
        notes: String? = nil,
        iconSymbolName: String,
        imageAssetName: String? = nil,
        isCustom: Bool = false,
        isFavorited: Bool = false,
        equipmentItems: [Equipment] = []
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.notes = notes
        self.iconSymbolName = iconSymbolName
        self.imageAssetName = imageAssetName
        self.isCustom = isCustom
        self.isFavorited = isFavorited || isCustom
        self.equipment = nil
        self.equipmentItems = equipmentItems
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
