import Foundation
import SwiftData

@Model
final class Equipment: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    var iconSymbolName: String = ""
    /// True for equipment the user created themselves, vs. seeded catalog equipment.
    var isCustom: Bool = false
    /// Deprecated — replaced by `isAtHome`/`isAtGym`. Kept only so
    /// `EquipmentHomeGymMigration` can read its old value once; nothing else
    /// reads or writes it anymore.
    var isFavorited: Bool = false
    var isAtHome: Bool = false
    var isAtGym: Bool = false
    /// On = variable-weight equipment (dumbbells, vests) that exposes weight-unit and
    /// available-weight settings. Off = passive equipment (mats, benches) needed to
    /// perform an exercise but with no adjustable weight of its own.
    var isWeighted: Bool = false
    /// nil = use the global `AppSettings.weightUnit` default.
    var preferredWeightUnit: String?
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// Optional at the type level (not just default-valued) — CloudKit requires every
    /// to-many relationship to be Optional; the non-optional `weightCombos` wrapper
    /// below keeps every other call site in the app unchanged.
    @Relationship(deleteRule: .cascade, inverse: \WeightCombo.equipment)
    var weightCombosStorage: [WeightCombo]?
    var weightCombos: [WeightCombo] {
        get { weightCombosStorage ?? [] }
        set { weightCombosStorage = newValue }
    }

    /// The many-to-many inverse of `Exercise.equipmentItemsStorage` — without this,
    /// SwiftData doesn't reliably treat the relationship as true many-to-many; each
    /// `Equipment` instance could only actually stay linked to one `Exercise` at a
    /// time, silently dropping every other exercise's link to the same equipment as
    /// later ones were seeded. The `@Relationship(inverse:)` annotation itself lives on
    /// the `Exercise` side; this is the plain matching property.
    var exercisesStorage: [Exercise]?
    var exercises: [Exercise] {
        get { exercisesStorage ?? [] }
        set { exercisesStorage = newValue }
    }

    /// Back-references that exist only to satisfy CloudKit's "every relationship needs
    /// an inverse" rule for `SetLog.equipment` and `RepSectionExercise.preferredEquipment`
    /// — nothing in the app reads or writes them.
    @Relationship(inverse: \SetLog.equipment)
    var setLogs: [SetLog]?

    @Relationship(inverse: \RepSectionExercise.preferredEquipment)
    var repSectionExercises: [RepSectionExercise]?

    @Relationship(inverse: \TimeSectionStep.preferredEquipment)
    var timeSectionSteps: [TimeSectionStep]?

    @Relationship(inverse: \PersonalRecord.equipment)
    var personalRecords: [PersonalRecord]?
    @Relationship(inverse: \PersonalRecordEntry.equipment)
    var personalRecordEntries: [PersonalRecordEntry]?

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
    }

    /// By weight, not by the order the rows happened to be created in. Nothing in the
    /// app lets these be arranged by hand, and everything that reads them — the ±
    /// stepper above all, which treats the list as a ladder from lightest to heaviest —
    /// assumes ascending. Deriving the order from the value also repairs a ladder that
    /// an earlier append or an import already left out of order.
    ///
    /// `sortOrder` survives as the tiebreak, so two entries with the same value keep a
    /// stable order, and so an exported archive still round-trips it.
    var sortedWeightCombos: [WeightCombo] {
        weightCombos
            .filter { $0.deletedAt == nil }
            .sorted { ($0.value, $0.sortOrder) < ($1.value, $1.sortOrder) }
    }

    var effectiveWeightUnit: String {
        preferredWeightUnit ?? AppSettings.weightUnit
    }

    /// Value of `preferredWeightUnit` that marks this equipment as option-based (an
    /// auto-incrementing number with an optional label/color) rather than kg/lb —
    /// unlike kg/lb, this is always an explicit per-equipment choice, never the global
    /// default, so it's only ever read from `preferredWeightUnit` directly.
    ///
    /// **The raw value stays `"level"` and must not change.** It is the string already
    /// written into `preferredWeightUnit` on every option-based equipment in every
    /// existing store and iCloud record; renaming it would orphan all of them. It is a
    /// storage token, never a label — the user-facing word is "Option", and nothing
    /// should print this string. "Level" belongs to exercise progressions, and a
    /// band-assisted pull-up would otherwise show both meanings in one card.
    static let optionUnit = "level"

    var usesOptions: Bool {
        preferredWeightUnit == Equipment.optionUnit
    }

    /// The next auto-incremented option number for this equipment — current highest
    /// value + 1 (or 1 if there are none yet). Same "current max + 1" convention used
    /// for `sortOrder` throughout this codebase.
    var nextOptionValue: Double {
        (sortedWeightCombos.map(\.value).max() ?? 0) + 1
    }
}
