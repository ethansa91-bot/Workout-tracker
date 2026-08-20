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

    @Relationship(inverse: \PersonalRecord.equipment)
    var personalRecords: [PersonalRecord]?

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

    var sortedWeightCombos: [WeightCombo] {
        weightCombos
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var effectiveWeightUnit: String {
        preferredWeightUnit ?? AppSettings.weightUnit
    }

    /// Value of `preferredWeightUnit` that marks this equipment as level-based (an
    /// auto-incrementing number with an optional label/color) rather than kg/lb —
    /// unlike kg/lb, "level" is always an explicit per-equipment choice, never the
    /// global default, so it's only ever read from `preferredWeightUnit` directly.
    static let levelUnit = "level"

    var isLevelBased: Bool {
        preferredWeightUnit == Equipment.levelUnit
    }

    /// The next auto-incremented level number for this equipment — current highest
    /// level value + 1 (or 1 if there are none yet). Same "current max + 1" convention
    /// used for `sortOrder` throughout this codebase.
    var nextLevelValue: Double {
        (sortedWeightCombos.map(\.value).max() ?? 0) + 1
    }
}
