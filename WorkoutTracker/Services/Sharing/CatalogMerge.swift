import Foundation
import SwiftData

/// Applies the user's decisions and hands back publisher-id → local-model maps, which is
/// exactly the shape `SharedWorkoutImporter.buildWorkout` already consumes.
///
/// **The invariant that makes this safe: a matched row is never duplicated and never
/// deleted.** `useTheirs` overwrites the fields of the *existing* object, so its identity
/// survives, and with it every reference already pointing at it —
/// `RepSectionExercise.exercise`, `SetLog.exercise`, `PersonalRecord.exercise`,
/// `TimeSectionStep.exercise`, `SectionExerciseEntry.exercise`,
/// `ExerciseSessionNote.exercise`. That is why nothing here has to repoint anything:
/// there is no losing copy to repoint away from. Contrast `CatalogReconciliation`, which
/// *does* delete a duplicate and therefore has to move every back-reference by hand.
@MainActor
enum CatalogMerge {

    /// Publisher ids mapped onto the local rows the workout should be built against.
    struct Resolved {
        var exercises: [UUID: Exercise] = [:]
        var equipment: [UUID: Equipment] = [:]
        var executionTypes: [UUID: ExecutionType] = [:]
        var muscles: [UUID: Muscle] = [:]
        var muscleCategories: [UUID: MuscleCategory] = [:]
        var exerciseCategories: [UUID: ExerciseCategory] = [:]
    }

    /// Applied in dependency order: categories before what belongs to them, muscles and
    /// equipment before the exercises that reference them.
    static func apply(
        _ plan: CatalogImportPlan,
        images: [String: Data],
        weightCombos: [ArchiveWeightCombo],
        context: ModelContext
    ) throws -> Resolved {
        var resolved = Resolved()

        let localMuscleCategories = try index(MuscleCategory.self, context: context)
        for decision in plan.muscleCategories {
            guard let model = resolve(
                decision,
                local: localMuscleCategories,
                create: {
                    let created = MuscleCategory(name: decision.incoming.name)
                    context.insert(created)
                    return created
                },
                overwrite: { $0.name = decision.incoming.name },
                merge: { _ in }
            ) else { continue }
            resolved.muscleCategories[decision.incomingID] = model
        }

        let localMuscles = try index(Muscle.self, context: context)
        for decision in plan.muscles {
            let dto = decision.incoming
            let categories = dto.categoryIDs.compactMap { resolved.muscleCategories[$0] }
            guard let model = resolve(
                decision,
                local: localMuscles,
                create: {
                    let created = Muscle(name: dto.name, iconSymbolName: dto.iconSymbolName)
                    context.insert(created)
                    created.categories = categories
                    return created
                },
                overwrite: {
                    $0.name = dto.name
                    $0.iconSymbolName = dto.iconSymbolName
                    $0.categories = union($0.categories, categories)
                },
                merge: {
                    $0.categories = union($0.categories, categories)
                    if $0.iconSymbolName.isEmpty { $0.iconSymbolName = dto.iconSymbolName }
                }
            ) else { continue }
            resolved.muscles[dto.id] = model
        }

        let localEquipment = try index(Equipment.self, context: context)
        // Grouped up front so a created equipment can be given its weight options.
        let combosByEquipment = Dictionary(grouping: weightCombos) { $0.equipmentID }
        for decision in plan.equipment {
            let dto = decision.incoming
            guard let model = resolve(
                decision,
                local: localEquipment,
                create: {
                    let created = Equipment(
                        name: dto.name,
                        iconSymbolName: dto.iconSymbolName,
                        isCustom: true,
                        isAtHome: dto.isAtHome,
                        isAtGym: dto.isAtGym,
                        isWeighted: dto.isWeighted,
                        preferredWeightUnit: dto.preferredWeightUnit
                    )
                    context.insert(created)
                    // Weight options are only ever seeded onto equipment this import
                    // creates. They describe the plates and dumbbells someone physically
                    // owns, so overwriting an existing item's set with a stranger's would
                    // be wrong however emphatically the user picked "use theirs".
                    for combo in combosByEquipment[dto.id] ?? [] {
                        context.insert(WeightCombo(
                            equipment: created,
                            value: combo.value,
                            sortOrder: combo.sortOrder,
                            label: combo.label,
                            color: combo.colorRaw.flatMap(PaletteColor.init(rawValue:))
                        ))
                    }
                    return created
                },
                overwrite: {
                    $0.name = dto.name
                    $0.iconSymbolName = dto.iconSymbolName
                    $0.isAtHome = dto.isAtHome
                    $0.isAtGym = dto.isAtGym
                    $0.isWeighted = dto.isWeighted
                    $0.preferredWeightUnit = dto.preferredWeightUnit
                },
                merge: {
                    if $0.iconSymbolName.isEmpty { $0.iconSymbolName = dto.iconSymbolName }
                    // Availability is additive: somewhere they train is somewhere it exists.
                    $0.isAtHome = $0.isAtHome || dto.isAtHome
                    $0.isAtGym = $0.isAtGym || dto.isAtGym
                }
            ) else { continue }
            resolved.equipment[dto.id] = model
        }

        let localExecutionTypes = try index(ExecutionType.self, context: context)
        for decision in plan.executionTypes {
            let dto = decision.incoming
            guard let model = resolve(
                decision,
                local: localExecutionTypes,
                create: {
                    // `isCustom: true` regardless of what the publisher had it as — on
                    // this device it is a type the user added, not one the app seeded,
                    // which is the same call `Equipment` and `Exercise` make above.
                    let created = ExecutionType(name: dto.name, isCustom: true)
                    context.insert(created)
                    return created
                },
                overwrite: { $0.name = dto.name },
                // Nothing but a name to fill in, so there is no gap a merge could close
                // that `keepMine` doesn't already handle.
                merge: { _ in }
            ) else { continue }
            resolved.executionTypes[dto.id] = model
        }

        let localExerciseCategories = try index(ExerciseCategory.self, context: context)
        for decision in plan.exerciseCategories {
            guard let model = resolve(
                decision,
                local: localExerciseCategories,
                create: {
                    let created = ExerciseCategory(name: decision.incoming.name)
                    context.insert(created)
                    return created
                },
                overwrite: { $0.name = decision.incoming.name },
                merge: { _ in }
            ) else { continue }
            resolved.exerciseCategories[decision.incomingID] = model
        }

        let localExercises = try index(Exercise.self, context: context)
        for decision in plan.exercises {
            let dto = decision.incoming
            let equipment = dto.equipmentIDs.compactMap { resolved.equipment[$0] }
            let executionTypes = dto.executionTypeIDs.compactMap { resolved.executionTypes[$0] }
            let muscles = dto.muscleIDs.compactMap { resolved.muscles[$0] }
            let categories = dto.categoryIDs.compactMap { resolved.exerciseCategories[$0] }

            guard let model = resolve(
                decision,
                local: localExercises,
                create: {
                    let created = Exercise(
                        name: dto.name,
                        label: dto.label,
                        notes: dto.notes,
                        videoURL: dto.videoURL,
                        iconSymbolName: dto.iconSymbolName,
                        imageAssetName: dto.imageAssetName,
                        isCustom: true,
                        allowsBodyweight: dto.allowsBodyweight,
                        isOneSided: dto.isOneSided,
                        defaultEquipmentName: dto.defaultEquipmentName
                    )
                    context.insert(created)
                    created.defaultsToBodyweight = dto.defaultsToBodyweight ?? false
                    created.equipmentItems = equipment
                    created.executionTypes = executionTypes
                    created.separateRecordsPerExecutionType = dto.separateRecordsPerExecutionType
                    created.muscles = muscles
                    created.categories = categories
                    adoptPhoto(dto, images: images, into: created, force: true)
                    return created
                },
                overwrite: {
                    $0.name = dto.name
                    $0.label = dto.label
                    $0.notes = dto.notes
                    $0.videoURL = dto.videoURL
                    $0.iconSymbolName = dto.iconSymbolName
                    $0.imageAssetName = dto.imageAssetName
                    $0.allowsBodyweight = dto.allowsBodyweight
                    $0.isOneSided = dto.isOneSided
                    $0.defaultEquipmentName = dto.defaultEquipmentName
                    $0.defaultsToBodyweight = dto.defaultsToBodyweight ?? false
                    // Relationships are unioned even here. Dropping a muscle or a piece
                    // of equipment the local exercise has would change what the user's
                    // existing filters and pickers show for a row they never edited.
                    $0.equipmentItems = union($0.equipmentItems, equipment)
                    $0.executionTypes = union($0.executionTypes, executionTypes)
                    // Not overwritten: whether the user keeps records apart is a decision
                    // about *their* history, and a publisher has no standing to reverse it.
                    // Union above can only add types, so an existing split stays valid.
                    $0.muscles = union($0.muscles, muscles)
                    $0.categories = union($0.categories, categories)
                    adoptPhoto(dto, images: images, into: $0, force: true)
                },
                merge: {
                    $0.equipmentItems = union($0.equipmentItems, equipment)
                    $0.executionTypes = union($0.executionTypes, executionTypes)
                    $0.muscles = union($0.muscles, muscles)
                    $0.categories = union($0.categories, categories)
                    if $0.iconSymbolName.isEmpty { $0.iconSymbolName = dto.iconSymbolName }
                    if isBlank($0.notes) { $0.notes = dto.notes }
                    if isBlank($0.videoURL) { $0.videoURL = dto.videoURL }
                    if $0.imageAssetName == nil { $0.imageAssetName = dto.imageAssetName }
                    adoptPhoto(dto, images: images, into: $0, force: false)
                }
            ) else { continue }
            resolved.exercises[dto.id] = model
        }

        return resolved
    }

    // MARK: - Applying one decision

    /// Returns the local model the publisher's id should map to, performing whatever
    /// write the chosen resolution implies. `nil` only when a `link` target has since
    /// vanished, in which case the reference is simply left unresolved rather than
    /// silently pointed at something else.
    private static func resolve<DTO, Model: PersistentModel & SyncableModel>(
        _ decision: CatalogDecision<DTO>,
        local: [UUID: Model],
        create: () -> Model,
        overwrite: (Model) -> Void,
        merge: (Model) -> Void
    ) -> Model? {
        switch decision.resolution {
        case .createNew:
            return create()

        case .link(let localID):
            return local[localID]

        case .identical, .keepMine:
            guard let localID = decision.localID else { return create() }
            return local[localID]

        case .useTheirs:
            guard let localID = decision.localID, let model = local[localID] else { return create() }
            overwrite(model)
            model.markDirty()
            return model

        case .merge:
            guard let localID = decision.localID, let model = local[localID] else { return create() }
            merge(model)
            model.markDirty()
            return model
        }
    }

    /// Writes an incoming generated photo to this device's store.
    ///
    /// `save` rather than `restore`: the filename is derived from the *local* exercise's
    /// id, so the picture belongs to the row that now owns it. `restore` keeps the
    /// archive's original name, which here would be the publisher's exercise id — a name
    /// nothing local points at.
    private static func adoptPhoto(
        _ dto: ArchiveExercise,
        images: [String: Data],
        into exercise: Exercise,
        force: Bool
    ) {
        guard let fileName = dto.generatedImageFileName, let data = images[fileName] else { return }

        if !force,
           let existing = exercise.generatedImageFileName,
           GeneratedExerciseImageStore.exists(fileName: existing) {
            // Merge fills gaps; it doesn't replace a picture the user already has.
            return
        }

        guard let saved = try? GeneratedExerciseImageStore.save(data, exerciseID: exercise.id) else { return }
        exercise.generatedImageFileName = saved
        exercise.generatedImageStyle = dto.generatedImageStyle
    }

    // MARK: - Helpers

    private static func index<T: PersistentModel & SyncableModel>(
        _ type: T.Type,
        context: ModelContext
    ) throws -> [UUID: T] {
        let rows = try context.fetch(FetchDescriptor<T>()).filter { $0.deletedAt == nil }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Concatenates two to-many relationships without repeating a model already in both.
    /// Same rule as `CatalogReconciliation.union`, which merges duplicate catalog rows.
    private static func union<T: PersistentModel>(_ lhs: [T], _ rhs: [T]) -> [T] {
        var result = lhs
        for item in rhs where !result.contains(where: { $0.persistentModelID == item.persistentModelID }) {
            result.append(item)
        }
        return result
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
