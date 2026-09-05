import Foundation
import SwiftData

@Model
final class Exercise: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    var label: String?
    var notes: String?
    var videoURL: String?
    var iconSymbolName: String = ""
    /// Asset catalog name of a reference photo in `Assets.xcassets/ExercisePhotos`,
    /// when one was matched from free-exercise-db at seed/import time. nil falls back
    /// to `iconSymbolName` everywhere photos aren't shown.
    var imageAssetName: String?
    /// Filename (not a full path) of an AI-generated image in
    /// `GeneratedExerciseImageStore`'s directory. Local-only, like `imageAssetName` —
    /// deliberately absent from `ExerciseDTO` so it's never part of the sync payload.
    /// Takes priority over `imageAssetName` wherever exercise photos are rendered.
    var generatedImageFileName: String?
    /// Raw value of the `ExerciseImageStyle` used to produce `generatedImageFileName`,
    /// so reopening the generator can default to the last style picked.
    var generatedImageStyle: String?
    var isCustom: Bool = false
    var isFavorited: Bool = false
    /// This exercise can also be done unloaded even though it has weighted equipment
    /// (a dip or pull-up that's sometimes weighted, sometimes not). Unlocks the
    /// per-workout bodyweight option on `RepSectionExercise`. Meaningless — and hidden
    /// in the UI — for an exercise with no weighted equipment, which is bodyweight
    /// already.
    var allowsBodyweight: Bool = false
    /// Trains one side at a time (split squats, single-arm rows). Unlocks the
    /// per-workout "track left/right separately" option.
    var isOneSided: Bool = false
    /// Keep a separate personal record per execution type, rather than one record for the
    /// exercise however it was performed. Only meaningful with more than one type
    /// attached, which is what `splitsRecordsByExecutionType` folds in — read that rather
    /// than this flag anywhere a record is being resolved. Non-optional with a `false`
    /// default so exercises written before this existed decode correctly.
    var separateRecordsPerExecutionType: Bool = false
    /// Name of the weighted item among `equipmentItems` to prefer when more than one
    /// is attached. nil (or a name no longer attached) falls back to the first, which
    /// is what every exercise did before this existed.
    ///
    /// A *name*, not an id, because hand-written seed JSON has to be able to say it —
    /// which does mean renaming the equipment silently orphans the choice.
    var defaultEquipmentName: String?
    /// This exercise means bodyweight by default even though weighted equipment is
    /// attached. `defaultEquipmentName` can't express this: it is looked up among the
    /// weighted items, and a sentinel string would collide with real equipment.
    ///
    /// Distinct from `allowsBodyweight`, which only says bodyweight is *permitted* — this
    /// makes it the starting selection. Non-optional with a `false` default so exercises
    /// written before it existed decode correctly; every one of them started loaded.
    var defaultsToBodyweight: Bool = false
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// Backing storage for `equipmentItems` — CloudKit requires to-many relationships
    /// to be Optional at the type level (a default value alone isn't enough), so the
    /// raw `@Relationship` is Optional and every other property in the app keeps using
    /// the non-optional computed wrapper below instead.
    @Relationship(inverse: \Equipment.exercisesStorage)
    var equipmentItemsStorage: [Equipment]?
    /// Empty = bodyweight, no equipment needed. Can mix passive and weighted equipment.
    var equipmentItems: [Equipment] {
        get { equipmentItemsStorage ?? [] }
        set { equipmentItemsStorage = newValue }
    }

    @Relationship(inverse: \Muscle.exercisesStorage)
    var musclesStorage: [Muscle]?
    var muscles: [Muscle] {
        get { musclesStorage ?? [] }
        set { musclesStorage = newValue }
    }

    /// The `@Relationship(inverse:)` annotation for this pair lives on `ExerciseCategory`.
    var categoriesStorage: [ExerciseCategory]?
    var categories: [ExerciseCategory] {
        get { categoriesStorage ?? [] }
        set { categoriesStorage = newValue }
    }

    /// Which ways of performing this exercise are offered when building a workout. Empty
    /// = no choice to make, and every picker for it stays hidden.
    @Relationship(inverse: \ExecutionType.exercisesStorage)
    var executionTypesStorage: [ExecutionType]?
    var executionTypes: [ExecutionType] {
        get { executionTypesStorage ?? [] }
        set { executionTypesStorage = newValue }
    }

    // The relationships below exist only so CloudKit's "every relationship needs an
    // inverse" rule is satisfied for the one-directional catalog lookups on the other
    // models (`PersonalRecord.exercise`, `RepSectionExercise.exercise`, etc.) — nothing
    // in the app reads or writes these back-references, so unlike the three above they
    // have no non-optional wrapper.
    @Relationship(inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord]?
    @Relationship(inverse: \PersonalRecordEntry.exercise)
    var personalRecordEntries: [PersonalRecordEntry]?
    @Relationship(inverse: \RepSectionExercise.exercise)
    var repSectionExercises: [RepSectionExercise]?
    @Relationship(inverse: \SectionExerciseEntry.exercise)
    var sectionExerciseEntries: [SectionExerciseEntry]?
    @Relationship(inverse: \SetLog.exercise)
    var setLogs: [SetLog]?
    @Relationship(inverse: \TimeSectionStep.exercise)
    var timeSectionSteps: [TimeSectionStep]?
    @Relationship(inverse: \ExerciseSessionNote.exercise)
    var exerciseSessionNotes: [ExerciseSessionNote]?

    /// Unlike the back-references above, this one *is* read: it is how an exercise finds
    /// the ladder it belongs to, and through it every other rung.
    @Relationship(inverse: \ProgressionStep.exercise)
    var progressionSteps: [ProgressionStep]?

    /// The user's personal nickname when set, falling back to the catalog `name`.
    var displayName: String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : name
    }

    /// Whether `name` is worth showing as a secondary line under `displayName` — true
    /// only when a label is set *and* it differs from `name` by more than case or
    /// whitespace (so "Front Squat" vs "front squat" doesn't count as different).
    var showsSecondaryName: Bool {
        guard let label else { return false }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        func normalized(_ s: String) -> String {
            s.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }
        return normalized(trimmed) != normalized(name)
    }

    // MARK: - Progression

    /// This exercise's rung, if it is on a ladder.
    ///
    /// An exercise belongs to at most one progression — the editor enforces it, and
    /// `first` here is what that assumption looks like in code. Two ladders claiming the
    /// same exercise would make "level up" ambiguous with no way to ask which was meant.
    var progressionStep: ProgressionStep? {
        // `$0.group?.deletedAt == nil` was the bug: optional-chaining a nil group yields
        // nil, and `nil == nil` is true, so a rung with *no group at all* passed as live.
        // Such a rung is invisible in the editor and unreachable by `unlink`, yet
        // `CatalogDeletionService` read it and refused to delete the exercise forever.
        // Requiring a real, live group is what makes an orphan simply not count.
        (progressionSteps ?? []).first {
            guard $0.deletedAt == nil, let group = $0.group else { return false }
            return group.deletedAt == nil
        }
    }

    /// Rungs pointing at no live ladder. Nothing should produce these, but a hard-deleted
    /// duplicate exercise or a partially-applied import can — and they used to be
    /// invisible *and* load-bearing, so `ProgressionSection` offers to clear them.
    var orphanedProgressionSteps: [ProgressionStep] {
        (progressionSteps ?? []).filter {
            guard $0.deletedAt == nil else { return false }
            guard let group = $0.group else { return true }
            return group.deletedAt != nil
        }
    }

    var progressionGroup: ProgressionGroup? { progressionStep?.group }

    var progressionLevel: Int? { progressionStep?.level }

    /// Live types in a stable display order — the choices every execution-type picker
    /// offers, and the list the "separate records" toggle counts.
    var sortedExecutionTypes: [ExecutionType] {
        executionTypes.filter { $0.deletedAt == nil }.sorted { $0.name < $1.name }
    }

    /// Whether records should actually be split by execution type right now.
    ///
    /// One attached type is enough: a set can always be logged without naming one, so a
    /// single type already separates "explosive" from "however I usually do it". The
    /// emptiness check remains only to stop an exercise with no types at all from
    /// splitting on a facet it cannot express.
    var splitsRecordsByExecutionType: Bool {
        separateRecordsPerExecutionType && !sortedExecutionTypes.isEmpty
    }

    /// The weighted items among `equipmentItems`, in a stable display order — the
    /// choices an entry's equipment picker offers.
    var weightedEquipmentOptions: [Equipment] {
        equipmentItems.filter(\.isWeighted).sorted { $0.name < $1.name }
    }

    /// Whether bodyweight is a legitimate load for this exercise: flagged for it in the
    /// catalog, or simply having no weighted equipment to load. One definition shared by
    /// the builder's picker, the runner's menu, and import, which previously disagreed —
    /// the menu offered Bodyweight off the catalog flag while the set row's Body position
    /// came from the per-entry toggle.
    var allowsBodyweightSource: Bool {
        weightedEquipmentOptions.isEmpty || allowsBodyweight
    }

    /// The weighted item among `equipmentItems`, if any — used to resolve weight
    /// options/unit. When several are attached, `defaultEquipmentName` picks which;
    /// without a usable choice the first is used, as it always was. Logging weight
    /// against multiple simultaneous equipment per set isn't supported.
    var weightedEquipment: Equipment? {
        let weighted = equipmentItems.filter(\.isWeighted)
        if let name = defaultEquipmentName,
           let chosen = weighted.first(where: { $0.name == name }) {
            return chosen
        }
        return weighted.first
    }

    /// What this exercise is loaded with when nothing else has said otherwise — nil for
    /// bodyweight, which is also what "no weighted equipment at all" resolves to.
    ///
    /// The single answer the builder's picker, both runners and the record pages read, so
    /// none of them can name a different default than the exercise page shows.
    /// `allowsBodyweightSource` is re-checked rather than trusted: turning "Allow
    /// bodyweight" back off would otherwise strand the exercise defaulting to a load it no
    /// longer offers, with the row that set it hidden and no way back.
    var defaultWeightedEquipment: Equipment? {
        guard !(defaultsToBodyweight && allowsBodyweightSource) else { return nil }
        return weightedEquipment
    }

    /// Whether there is more than one answer worth asking about. Bodyweight counts as a
    /// real alternative, so a single weighted item plus bodyweight is still a choice.
    var hasEquipmentChoice: Bool {
        weightedEquipmentOptions.count > 1
            || (allowsBodyweight && !weightedEquipmentOptions.isEmpty)
    }

    init(
        id: UUID = UUID(),
        name: String,
        label: String? = nil,
        notes: String? = nil,
        videoURL: String? = nil,
        iconSymbolName: String,
        imageAssetName: String? = nil,
        isCustom: Bool = false,
        isFavorited: Bool = false,
        allowsBodyweight: Bool = false,
        isOneSided: Bool = false,
        defaultEquipmentName: String? = nil,
        equipmentItems: [Equipment] = [],
        executionTypes: [ExecutionType] = []
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.notes = notes
        self.videoURL = videoURL
        self.iconSymbolName = iconSymbolName
        self.imageAssetName = imageAssetName
        self.generatedImageFileName = nil
        self.generatedImageStyle = nil
        self.isCustom = isCustom
        self.isFavorited = isFavorited || isCustom
        self.allowsBodyweight = allowsBodyweight
        self.isOneSided = isOneSided
        self.defaultEquipmentName = defaultEquipmentName
        self.equipmentItemsStorage = equipmentItems
        self.executionTypesStorage = executionTypes
        self.separateRecordsPerExecutionType = false
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
