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
        let incomingExecutionTypeNames = Dictionary(
            payload.executionTypes.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
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

        // --- Execution types ---------------------------------------------------
        // Name-matched like everything else here, which is what stops a download minting
        // a second "Explosive" beside the recipient's own.
        let localExecutionTypes = try live(ExecutionType.self, context: context)
        let executionTypeIndex = Index(localExecutionTypes, name: \.name, id: \.id)
        plan.executionTypes = payload.executionTypes.map { dto in
            decide(dto, id: dto.id, name: dto.name, in: executionTypeIndex) { local in
                [difference("Name", local.name, dto.name)].compactMap { $0 }
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
        var referenced = bundles.reduce(into: Set<UUID>()) { ids, bundle in
            ids.formUnion(referencedExerciseIDs(in: bundle.payload.workout))
        }
        // Ladder members too, or they are never planned, never resolved, and their rungs
        // land pointing at nothing — which used to make the exercise undeletable. This
        // filter's whole job is to drop manifest exercises the workout doesn't use, and a
        // progression is the one case where it must not.
        for step in payload.progressionSteps {
            if let id = step.exerciseID { referenced.insert(id) }
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
                        // Both were missing, and `CatalogMerge.overwrite` writes both — so
                        // accepting a shared exercise silently reassigned which equipment
                        // it means by default, with nothing on this screen to say so.
                        difference(
                            "Default equipment",
                            local.defaultsToBodyweight ? "Bodyweight" : (local.defaultEquipmentName ?? "—"),
                            (dto.defaultsToBodyweight ?? false) ? "Bodyweight" : (dto.defaultEquipmentName ?? "—")
                        ),
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
                        difference(
                            "Execution types",
                            list(local.executionTypes.filter { $0.deletedAt == nil }.map(\.name)),
                            list(dto.executionTypeIDs.compactMap { incomingExecutionTypeNames[$0] })
                        ),
                    ].compactMap { $0 }
                }
            }

        plan.progressions = planProgressions(payload, plan: plan, context: context)
        return plan
    }

    /// Matches incoming ladders against the recipient's structurally — by which exercises
    /// they hold once those have been resolved to local rows.
    ///
    /// The resolution defaults to `.keepMine` on a clash and `.useTheirs` otherwise. That
    /// asymmetry is deliberate: adding a ladder where there was none takes nothing away,
    /// while replacing one silently would discard a setup the user built by hand.
    private static func planProgressions(
        _ payload: SharedWorkoutPayload,
        plan: CatalogImportPlan,
        context: ModelContext
    ) -> ProgressionImportPlan {
        guard !payload.progressionSteps.isEmpty else { return ProgressionImportPlan() }

        let incomingNames = Dictionary(
            payload.exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        // Where each incoming exercise would land locally, given the exercise decisions
        // already made above — a `.link` points somewhere else entirely, and that is
        // exactly the case that can drag an untouched local exercise onto a ladder.
        let localExercises = (try? live(Exercise.self, context: context)) ?? []
        let localByID = Dictionary(localExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var landsOn: [UUID: Exercise] = [:]
        for decision in plan.exercises {
            switch decision.resolution {
            case .createNew:
                continue
            case .link(let localID):
                landsOn[decision.incomingID] = localByID[localID]
            case .identical, .keepMine, .useTheirs, .merge:
                landsOn[decision.incomingID] = decision.localID.flatMap { localByID[$0] }
            }
        }

        let workoutReferenced = referencedExerciseIDs(in: payload.workout)
        let stepsByGroup = Dictionary(grouping: payload.progressionSteps, by: { $0.groupID })

        return ProgressionImportPlan(decisions: payload.progressionGroups.compactMap { group in
            let steps = (stepsByGroup[group.id] ?? []).sorted { $0.level < $1.level }
            guard steps.count > 1 else { return nil }

            // Which of the recipient's ladders would end up holding one of these
            // exercises. This is the state the app cannot represent.
            var conflictingGroups: [UUID: ProgressionGroup] = [:]
            var clashingIncomingIDs: Set<UUID> = []
            for step in steps {
                guard let incomingID = step.exerciseID,
                      let local = landsOn[incomingID],
                      let localGroup = local.progressionGroup
                else { continue }
                conflictingGroups[localGroup.id] = localGroup
                clashingIncomingIDs.insert(incomingID)
            }

            let rungs = steps.compactMap { step -> ProgressionDecision.Rung? in
                guard let incomingID = step.exerciseID else { return nil }
                let name = landsOn[incomingID]?.displayName ?? incomingNames[incomingID] ?? "Exercise"
                return ProgressionDecision.Rung(
                    id: step.id,
                    level: step.level,
                    name: name,
                    clashes: clashingIncomingIDs.contains(incomingID)
                )
            }

            // Named for the review screen: what this ladder puts in the library that the
            // workout alone would not have.
            let added = steps
                .compactMap(\.exerciseID)
                .filter { !workoutReferenced.contains($0) && landsOn[$0] == nil }
                .compactMap { incomingNames[$0] }
                .sorted()

            return ProgressionDecision(
                incomingID: group.id,
                incomingRungs: rungs,
                conflicts: conflictingGroups.values.map { local in
                    ProgressionDecision.LocalLadder(
                        id: local.id,
                        rungs: local.sortedSteps.map { step in
                            ProgressionDecision.Rung(
                                id: step.id,
                                level: step.level,
                                name: step.exercise?.displayName ?? "Exercise",
                                clashes: false
                            )
                        }
                    )
                },
                addedExerciseNames: added,
                resolution: conflictingGroups.isEmpty ? .useTheirs : .keepMine
            )
        })
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
        result.executionTypes = dedupe(payloads.flatMap(\.executionTypes), id: \.id)
        result.muscles = dedupe(payloads.flatMap(\.muscles), id: \.id)
        result.muscleCategories = dedupe(payloads.flatMap(\.muscleCategories), id: \.id)
        result.exerciseCategories = dedupe(payloads.flatMap(\.exerciseCategories), id: \.id)
        result.weightCombos = dedupe(payloads.flatMap(\.weightCombos), id: \.id)
        result.progressionGroups = dedupe(payloads.flatMap(\.progressionGroups), id: \.id)
        result.progressionSteps = dedupe(payloads.flatMap(\.progressionSteps), id: \.id)
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
