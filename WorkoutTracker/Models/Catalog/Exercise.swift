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

    // The relationships below exist only so CloudKit's "every relationship needs an
    // inverse" rule is satisfied for the one-directional catalog lookups on the other
    // models (`PersonalRecord.exercise`, `RepSectionExercise.exercise`, etc.) — nothing
    // in the app reads or writes these back-references, so unlike the three above they
    // have no non-optional wrapper.
    @Relationship(inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord]?
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
        videoURL: String? = nil,
        iconSymbolName: String,
        imageAssetName: String? = nil,
        isCustom: Bool = false,
        isFavorited: Bool = false,
        allowsBodyweight: Bool = false,
        isOneSided: Bool = false,
        equipmentItems: [Equipment] = []
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
        self.equipmentItemsStorage = equipmentItems
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
