import Foundation
import SwiftData

/// One achievable weight value for a piece of owned equipment (e.g. one entry per
/// available dumbbell/plate combo). Modeled as its own row, not a JSON array, so each
/// value gets independent tombstone/dirty tracking like every other synced entity.
@Model
final class WeightCombo: SyncableModel {
    @Attribute(.unique) var id: UUID
    var equipment: Equipment?
    var value: Double
    var sortOrder: Int
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    init(id: UUID = UUID(), equipment: Equipment? = nil, value: Double, sortOrder: Int) {
        self.id = id
        self.equipment = equipment
        self.value = value
        self.sortOrder = sortOrder
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }
}
