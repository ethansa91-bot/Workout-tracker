import Foundation
import SwiftData

/// Works out what a download *would* do to the local catalog, writing nothing.
///
/// **Matching is by id first, normalized name second.** The id half matters more than it
/// looks: `SeedIdentity` derives seeded catalog ids as `SHA256("<namespace>|<name>")`, so
/// two people who seeded the same catalog genuinely hold the *same* UUID for "Barbell" —
/// the ids only diverge for custom rows. Matching on id therefore lines seeded rows up
/// even when one side has renamed something, and the name pass catches the rest.
@MainActor
enum CatalogImportPlanner {

    static func plan(_ bundles: [SharedWorkoutBundle], context: ModelContext) throws -> CatalogImportPlan {
        // Several workouts at once are planned as one catalog: their manifests overlap
        // heavily, and a shared exercise must produce a single decision rather than one
        // per workout that could contradict the others.
        guard let payload = merged(bundles) else { return CatalogImportPlan() }
        let images = bundles.reduce(into: [String: Data]()) { merged, bundle in
            merged.merge(bundle.images) { _, new in new }
        }
        var plan = CatalogImportPlan()

        // Names for the incoming side of a relationship diff — the payload speaks in the
        // publisher's ids, which mean nothing to a person reading the comparison.
        let incomingMuscleNames = Dictionary(
            payload.muscles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        let incomingEquipmentNames = Dictionary(
            payload.equipment.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        let incomingExerciseCategoryNames = Dictionary(
            payload.exerciseCategories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        let incomingMuscleCategoryNames = Dictionary(
            payload.muscleCategories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )

        // --- Muscle categories ------------------------------------------------
        let localMuscleCategories = try live(MuscleCategory.self, context: context)
        let muscleCategoryIndex = Index(localMuscleCategories, name: \.name, id: \.id)
        plan.muscleCategories = payload.muscleCategories.map { dto in
            decide(dto, id: dto.id, name: dto.name, in: muscleCategoryIndex) { local in
                [difference("Name", local.name, dto.name)].compactMap { $0 }
            }
        }

        // --- Muscles ----------------------------------------------------------
        let localMuscles = try live(Muscle.self, context: context)
        let muscleIndex = Index(localMuscles, name: \.name, id: \.id)
        plan.muscles = payload.muscles.map { dto in
            decide(dto, id: dto.id, name: dto.name, in: muscleIndex) { local in
                [
                    difference("Name", local.name, dto.name),
                    difference("Icon", local.iconSymbolName, dto.iconSymbolName),
                    difference(
                        "Categories",
                        list(local.categories.filter { $0.deletedAt == nil }.map(\.name)),
                        list(dto.categoryIDs.compactMap { incomingMuscleCategoryNames[$0] })
                    ),
                ].compactMap { $0 }
            }
        }

        // --- Equipment --------------------------------------------------------
        let localEquipment = try live(Equipment.self, context: context)
        let equipmentIndex = Index(localEquipment, name: \.name, id: \.id)
        plan.equipment = payload.equipment.map { dto in
            decide(dto, id: dto.id, name: dto.name, in: equipmentIndex) { local in
                [
                    difference("Name", local.name, dto.name),
                    difference("Icon", local.iconSymbolName, dto.iconSymbolName),
                    difference("At home", yesNo(local.isAtHome), yesNo(dto.isAtHome)),
                    difference("At gym", yesNo(local.isAtGym), yesNo(dto.isAtGym)),
                    difference("Weighted", yesNo(local.isWeighted), yesNo(dto.isWeighted)),
                    difference(
                        "Weight unit",
                        local.preferredWeightUnit ?? "Default",
                        dto.preferredWeightUnit ?? "Default"
                    ),
                ].compactMap { $0 }
            }
        }

        // --- Exercise categories ----------------------------------------------
        let localExerciseCategories = try live(ExerciseCategory.self, context: context)
        let exerciseCategoryIndex = Index(localExerciseCategories, name: \.name, id: \.id)
        plan.exerciseCategories = payload.exerciseCategories.map { dto in
            decide(dto, id: dto.id, name: dto.name, in: exerciseCategoryIndex) { local in
                [difference("Name", local.name, dto.name)].compactMap { $0 }
            }
        }

        // --- Exercises ---------------------------------------------------------
        // Only the ones some workout in the plan actually references. The manifests may
        // carry more, and one workout's manifest may carry exercises only another uses.
        let referenced = bundles.reduce(into: Set<UUID>()) { ids, bundle in
            ids.formUnion(referencedExerciseIDs(in: bundle.payload.workout))
        }
        let localExercises = try live(Exercise.self, context: context)
        let exerciseIndex = Index(localExercises, name: \.name, id: \.id)
        plan.exercises = payload.exercises
            .filter { referenced.contains($0.id) }
            .map { dto in
                decide(dto, id: dto.id, name: dto.name, in: exerciseIndex) { local in
                    [
                        difference("Name", local.name, dto.name),
                        difference("Nickname", local.label ?? "—", dto.label ?? "—"),
                        difference("Notes", local.notes ?? "—", dto.notes ?? "—"),
                        difference("Video", local.videoURL ?? "—", dto.videoURL ?? "—"),
                        difference("Icon", local.iconSymbolName, dto.iconSymbolName),
                        difference("Photo", photoLabel(local), photoLabel(dto, images: images)),
                        difference("Bodyweight", yesNo(local.allowsBodyweight), yesNo(dto.allowsBodyweight)),
                        difference("One-sided", yesNo(local.isOneSided), yesNo(dto.isOneSided)),
                        difference(
                            "Muscles",
                            list(local.muscles.filter { $0.deletedAt == nil }.map(\.name)),
                            list(dto.muscleIDs.compactMap { incomingMuscleNames[$0] })
                        ),
                        difference(
                            "Equipment",
                            list(local.equipmentItems.filter { $0.deletedAt == nil }.map(\.name)),
                            list(dto.equipmentIDs.compactMap { incomingEquipmentNames[$0] })
                        ),
                        difference(
                            "Categories",
                            list(local.categories.filter { $0.deletedAt == nil }.map(\.name)),
                            list(dto.categoryIDs.compactMap { incomingExerciseCategoryNames[$0] })
                        ),
                    ].compactMap { $0 }
                }
            }

        return plan
    }

    /// Every bundle's catalog folded into one, deduplicated by the publisher's ids.
    ///
    /// `workout` on the result is only a placeholder — the merged payload exists for its
    /// catalog arrays, and the workouts are built from their own bundles.
    private static func merged(_ bundles: [SharedWorkoutBundle]) -> SharedWorkoutPayload? {
        func dedupe<T>(_ items: [T], id: (T) -> UUID) -> [T] {
            var seen: Set<UUID> = []
            return items.filter { seen.insert(id($0)).inserted }
        }

        let payloads = bundles.map(\.payload)
        guard var result = payloads.first else { return nil }
        result.exercises = dedupe(payloads.flatMap(\.exercises), id: \.id)
        result.equipment = dedupe(payloads.flatMap(\.equipment), id: \.id)
        result.muscles = dedupe(payloads.flatMap(\.muscles), id: \.id)
        result.muscleCategories = dedupe(payloads.flatMap(\.muscleCategories), id: \.id)
        result.exerciseCategories = dedupe(payloads.flatMap(\.exerciseCategories), id: \.id)
        result.weightCombos = dedupe(payloads.flatMap(\.weightCombos), id: \.id)
        return result
    }

    // MARK: - Matching

    /// Id and normalized-name lookups over one model type.
    private struct Index<Model: SyncableModel> {
        private let nameKeyPath: KeyPath<Model, String>
        private let byID: [UUID: Model]
        private let byExactName: [String: Model]
        private let byNormalizedName: [String: Model]

        init(_ rows: [Model], name: KeyPath<Model, String>, id: KeyPath<Model, UUID>) {
            nameKeyPath = name
            // `uniquingKeysWith: first` throughout: a store carrying pre-existing
            // duplicates resolves to one stable winner rather than trapping.
            byID = Dictionary(rows.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
            byExactName = Dictionary(
                rows.map { ($0[keyPath: name], $0) }, uniquingKeysWith: { first, _ in first }
            )
            byNormalizedName = Dictionary(
                rows.map { (CatalogImportPlanner.normalize($0[keyPath: name]), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        func match(id: UUID, name: String) -> Model? {
            byID[id] ?? byExactName[name] ?? byNormalizedName[CatalogImportPlanner.normalize(name)]
        }

        func name(of model: Model) -> String { model[keyPath: nameKeyPath] }
    }

    private static func decide<DTO, Model: SyncableModel>(
        _ dto: DTO,
        id: UUID,
        name: String,
        in index: Index<Model>,
        differences: (Model) -> [CatalogDifference]
    ) -> CatalogDecision<DTO> {
        guard let local = index.match(id: id, name: name) else {
            return CatalogDecision(
                incoming: dto, incomingID: id, incomingName: name,
                localID: nil, localName: nil, differences: [], resolution: .createNew
            )
        }

        let diffs = differences(local)
        return CatalogDecision(
            incoming: dto, incomingID: id, incomingName: name,
            localID: local.id, localName: index.name(of: local),
            differences: diffs,
            // Merge is the non-destructive default: it never discards what the user has,
            // it only fills gaps and unions relationships.
            resolution: diffs.isEmpty ? .identical : .merge
        )
    }

    /// Trim + lowercase — the same rule `WorkoutImportService.ExerciseResolver` uses,
    /// kept identical so matching behaves the way the rest of the app's name resolution
    /// already does.
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Difference rendering

    private static func difference(_ field: String, _ mine: String, _ theirs: String) -> CatalogDifference? {
        guard mine != theirs else { return nil }
        return CatalogDifference(field: field, mine: mine, theirs: theirs)
    }

    private static func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "None" : names.sorted().joined(separator: ", ")
    }

    private static func photoLabel(_ exercise: Exercise) -> String {
        if let file = exercise.generatedImageFileName, GeneratedExerciseImageStore.exists(fileName: file) {
            return "Generated"
        }
        return exercise.imageAssetName == nil ? "None" : "Reference photo"
    }

    private static func photoLabel(_ dto: ArchiveExercise, images: [String: Data]) -> String {
        if let file = dto.generatedImageFileName, images[file] != nil { return "Generated" }
        return dto.imageAssetName == nil ? "None" : "Reference photo"
    }

    // MARK: - Helpers

    private static func live<T: PersistentModel & SyncableModel>(
        _ type: T.Type,
        context: ModelContext
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>()).filter { $0.deletedAt == nil }
    }

    /// Every exercise id the workout actually references, across all three section
    /// shapes. The payload may carry more than the workout uses; only these matter.
    static func referencedExerciseIDs(in workout: ArchiveWorkout) -> Set<UUID> {
        var ids: Set<UUID> = []
        for section in workout.sections where section.deletedAt == nil {
            for step in section.timeSteps where step.deletedAt == nil {
                if let id = step.exerciseID { ids.insert(id) }
            }
            for entry in section.repExercises where entry.deletedAt == nil {
                if let id = entry.exerciseID { ids.insert(id) }
            }
            // Quick entries are easy to forget — `WorkoutImportService.ExerciseResolver`
            // omits them, so EMOM/AMRAP exercises go unvalidated there. Included here.
            for entry in section.quickExercises where entry.deletedAt == nil {
                if let id = entry.exerciseID { ids.insert(id) }
            }
        }
        return ids
    }
}
