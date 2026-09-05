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
    /// equipment is option-based, the option number itself (1, 2, 3, ...).
    var value: Double = 0
    var sortOrder: Int = 0
    /// Option-only: an optional custom name (e.g. "Light", "Red") shown after the
    /// option's number. Unused for kg/lb combos.
    var label: String?
    /// Option-only: backing storage for `color`. Unused for kg/lb combos.
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

    /// Option-only display name — "3. Red" when the option carries a name, "opt. 3" when
    /// it doesn't. Shared by every place an option needs to be shown (set logging,
    /// personal records, history).
    ///
    /// The number leads even when there is a name, because the ladder is ordered and the
    /// name usually isn't: "Red" alone doesn't say whether the next tap goes heavier or
    /// lighter, and a colour name says nothing at all about where it sits.
    var optionDisplayName: String {
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(Int(value)). \(label)"
        }
        return WeightCombo.optionDisplayName(for: value)
    }

    /// The bare form, for a value the equipment has no option for — a weight typed on the
    /// wheel rather than picked off the ladder.
    static func optionDisplayName(for value: Double) -> String {
        "opt. \(Int(value))"
    }

    /// The option matching `value` on a ladder, by name where it has one.
    ///
    /// Every screen showing an option weight resolves it this way; before this existed
    /// the lookup-then-fall-back was copied into set logging, records, history and the
    /// runner, four times over.
    static func optionDisplayName(for value: Double, in options: [WeightCombo]) -> String {
        options.first(where: { $0.value == value })?.optionDisplayName
            ?? optionDisplayName(for: value)
    }
}
