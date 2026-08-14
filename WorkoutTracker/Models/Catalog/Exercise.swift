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

    /// nil = bodyweight, no equipment needed.
    var equipment: Equipment?
    var muscles: [Muscle] = []
    var categories: [ExerciseCategory] = []

    init(
        id: UUID = UUID(),
        name: String,
        label: String? = nil,
        notes: String? = nil,
        iconSymbolName: String,
        imageAssetName: String? = nil,
        isCustom: Bool = false,
        isFavorited: Bool = false,
        equipment: Equipment? = nil
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.notes = notes
        self.iconSymbolName = iconSymbolName
        self.imageAssetName = imageAssetName
        self.isCustom = isCustom
        self.isFavorited = isFavorited || isCustom
        self.equipment = equipment
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
