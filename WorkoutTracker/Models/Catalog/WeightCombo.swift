import Foundation
import SwiftData

/// One achievable weight value for a piece of owned equipment (e.g. one entry per
/// available dumbbell/plate combo). Modeled as its own row, not a JSON array, so each
/// value gets independent tombstone/dirty tracking like every other synced entity.
@Model
final class WeightCombo: SyncableModel {
    var id: UUID = UUID()
    var equipment: Equipment?
    /// The weight value in `Equipment.effectiveWeightUnit`'s unit — or, when the
    /// equipment's unit is `"level"`, the level number itself (1, 2, 3, ...).
    var value: Double = 0
    var sortOrder: Int = 0
    /// Level-only: an optional custom name (e.g. "Light", "Red") shown instead of
    /// "Level N". Unused for kg/lb combos.
    var label: String?
    /// Level-only: backing storage for `color`. Unused for kg/lb combos.
    var colorRaw: String?
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var color: PaletteColor? {
        get { colorRaw.flatMap(PaletteColor.init(rawValue:)) }
        set { colorRaw = newValue?.rawValue }
    }

    init(id: UUID = UUID(), equipment: Equipment? = nil, value: Double, sortOrder: Int, label: String? = nil, color: PaletteColor? = nil) {
        self.id = id
        self.equipment = equipment
        self.value = value
        self.sortOrder = sortOrder
        self.label = label
        self.colorRaw = color?.rawValue
        self.updatedAt = .now
        self.deletedAt = nil
    }

    /// Level-only display name — the custom label if set, else "Level N". Shared by
    /// every place a level needs to be shown (set logging, personal records, history).
    var levelDisplayName: String {
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        return "Level \(Int(value))"
    }
}
