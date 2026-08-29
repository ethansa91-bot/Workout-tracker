import Foundation
import SwiftData

/// Turns a local `Workout` into the bundle another user can download.
///
/// The workout itself maps straight through `ArchiveExportService.workoutOut` — sharing
/// and archiving use the same wire format. The work here is collecting the **catalog
/// closure**: walking every section to find which exercises the workout depends on, then
/// following those exercises out to their equipment, muscles and categories, so the
/// recipient receives a catalog they can actually reconstruct rather than a set of names.
@MainActor
enum SharedWorkoutBuilder {

    static func makeBundle(for workout: Workout) -> SharedWorkoutBundle {
        var dto = ArchiveExportService.workoutOut(workout)

        // Sharing publishes only live rows. Tombstones exist so a *backup* can reproduce
        // deletions; sending someone else's library a deleted section would be noise.
        dto.sections = dto.sections
            .filter { $0.deletedAt == nil }
            .map { section in
                var copy = section
                copy.timeSteps = section.timeSteps.filter { $0.deletedAt == nil }
                copy.repExercises = section.repExercises.filter { $0.deletedAt == nil }
                copy.quickExercises = section.quickExercises.filter { $0.deletedAt == nil }
                return copy
            }

        let catalog = referencedCatalog(for: workout)

        let payload = SharedWorkoutPayload(
            formatVersion: SharedWorkoutPayload.currentVersion,
            workout: dto,
            exercises: catalog.exercises,
            equipment: catalog.equipment,
            muscles: catalog.muscles,
            muscleCategories: catalog.muscleCategories,
            exerciseCategories: catalog.exerciseCategories,
            weightCombos: catalog.weightCombos
        )
        return SharedWorkoutBundle(payload: payload, images: catalog.images)
    }

    private struct Catalog {
        var exercises: [ArchiveExercise] = []
        var equipment: [ArchiveEquipment] = []
        var muscles: [ArchiveMuscle] = []
        var muscleCategories: [ArchiveMuscleCategory] = []
        var exerciseCategories: [ArchiveExerciseCategory] = []
        var weightCombos: [ArchiveWeightCombo] = []
        var images: [String: Data] = [:]
    }

    /// Everything this workout transitively touches, deduplicated.
    ///
    /// All three section shapes have to be walked — `.time` steps, `.rep` exercises, and
    /// the `.emom`/`.amrap` quick entries. Missing any one of them would publish a
    /// workout whose recipient can't resolve part of it.
    private static func referencedCatalog(for workout: Workout) -> Catalog {
        var exercisesByID: [UUID: Exercise] = [:]
        var equipmentByID: [UUID: Equipment] = [:]

        for section in workout.sortedSections {
            for step in section.sortedTimeSteps {
                if let exercise = step.exercise { exercisesByID[exercise.id] = exercise }
            }
            for entry in section.sortedRepExercises {
                if let exercise = entry.exercise { exercisesByID[exercise.id] = exercise }
                // A preferred equipment is normally also in the exercise's own list, but
                // an entry can outlive that link — collected explicitly so the reference
                // in the workout always resolves.
                if let equipment = entry.preferredEquipment { equipmentByID[equipment.id] = equipment }
            }
            for entry in section.sortedQuickExercises {
                if let exercise = entry.exercise { exercisesByID[exercise.id] = exercise }
            }
        }

        // Follow each exercise out to the rest of the catalog. This is the part v1
        // omitted, which is why downloaded exercises arrived with no muscles, no
        // equipment and no categories.
        var musclesByID: [UUID: Muscle] = [:]
        var muscleCategoriesByID: [UUID: MuscleCategory] = [:]
        var exerciseCategoriesByID: [UUID: ExerciseCategory] = [:]

        for exercise in exercisesByID.values {
            for equipment in exercise.equipmentItems where equipment.deletedAt == nil {
                equipmentByID[equipment.id] = equipment
            }
            for muscle in exercise.muscles where muscle.deletedAt == nil {
                musclesByID[muscle.id] = muscle
                for category in muscle.categories where category.deletedAt == nil {
                    muscleCategoriesByID[category.id] = category
                }
            }
            for category in exercise.categories where category.deletedAt == nil {
                exerciseCategoriesByID[category.id] = category
            }
        }

        var catalog = Catalog()
        catalog.exercises = exercisesByID.values.sorted { $0.name < $1.name }.map(exerciseOut)
        catalog.equipment = equipmentByID.values.sorted { $0.name < $1.name }.map(equipmentOut)
        catalog.muscles = musclesByID.values.sorted { $0.name < $1.name }.map(muscleOut)
        catalog.muscleCategories = muscleCategoriesByID.values
            .sorted { $0.name < $1.name }
            .map { ArchiveMuscleCategory(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, deletedAt: nil) }
        catalog.exerciseCategories = exerciseCategoriesByID.values
            .sorted { $0.name < $1.name }
            .map { ArchiveExerciseCategory(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, deletedAt: nil) }
        catalog.weightCombos = equipmentByID.values
            .flatMap(\.sortedWeightCombos)
            .map(weightComboOut)

        // The photo bytes, verbatim rather than decoded and re-encoded — the same reason
        // `ArchiveExportService.copyGeneratedImages` reaches for `data(fileName:)`.
        for exercise in exercisesByID.values {
            guard let fileName = exercise.generatedImageFileName,
                  let data = GeneratedExerciseImageStore.data(fileName: fileName)
            else { continue }
            catalog.images[fileName] = data
        }

        return catalog
    }

    /// Unlike v1, this carries the relationship ids and the generated photo's filename:
    /// the manifest now contains the rows those ids refer to, and the bytes ship in the
    /// bundle's image zip, so both finally mean something on the other side.
    private static func exerciseOut(_ exercise: Exercise) -> ArchiveExercise {
        ArchiveExercise(
            id: exercise.id,
            name: exercise.name,
            label: exercise.label,
            notes: exercise.notes,
            videoURL: exercise.videoURL,
            iconSymbolName: exercise.iconSymbolName,
            // An asset-catalog name is compiled into every copy of the app, so this one
            // resolves on the recipient's device without any bytes travelling at all.
            imageAssetName: exercise.imageAssetName,
            generatedImageFileName: exercise.generatedImageFileName,
            generatedImageStyle: exercise.generatedImageStyle,
            isCustom: exercise.isCustom,
            isFavorited: false,
            allowsBodyweight: exercise.allowsBodyweight,
            isOneSided: exercise.isOneSided,
            defaultEquipmentName: exercise.defaultEquipmentName,
            equipmentIDs: exercise.equipmentItems.filter { $0.deletedAt == nil }.map(\.id),
            muscleIDs: exercise.muscles.filter { $0.deletedAt == nil }.map(\.id),
            categoryIDs: exercise.categories.filter { $0.deletedAt == nil }.map(\.id),
            updatedAt: exercise.updatedAt,
            deletedAt: nil
        )
    }

    private static func equipmentOut(_ equipment: Equipment) -> ArchiveEquipment {
        ArchiveEquipment(
            id: equipment.id,
            name: equipment.name,
            iconSymbolName: equipment.iconSymbolName,
            isCustom: equipment.isCustom,
            isFavorited: false,
            isAtHome: equipment.isAtHome,
            isAtGym: equipment.isAtGym,
            isWeighted: equipment.isWeighted,
            preferredWeightUnit: equipment.preferredWeightUnit,
            updatedAt: equipment.updatedAt,
            deletedAt: nil
        )
    }

    private static func muscleOut(_ muscle: Muscle) -> ArchiveMuscle {
        ArchiveMuscle(
            id: muscle.id,
            name: muscle.name,
            iconSymbolName: muscle.iconSymbolName,
            categoryIDs: muscle.categories.filter { $0.deletedAt == nil }.map(\.id),
            updatedAt: muscle.updatedAt,
            deletedAt: nil
        )
    }

    private static func weightComboOut(_ combo: WeightCombo) -> ArchiveWeightCombo {
        ArchiveWeightCombo(
            id: combo.id,
            equipmentID: combo.equipment?.id,
            value: combo.value,
            sortOrder: combo.sortOrder,
            label: combo.label,
            colorRaw: combo.colorRaw,
            updatedAt: combo.updatedAt,
            deletedAt: nil
        )
    }
}
