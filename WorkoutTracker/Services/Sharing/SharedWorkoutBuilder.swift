import Foundation
import SwiftData

/// Turns a local `Workout` into the payload another user can download.
///
/// The workout itself maps straight through `ArchiveExportService.workoutOut` — sharing
/// and archiving use the same wire format. The work here is collecting the **exercise
/// manifest**: walking every section to find which catalog rows the workout actually
/// depends on, so the recipient can match them by name and create anything missing.
@MainActor
enum SharedWorkoutBuilder {

    static func makePayload(for workout: Workout) -> SharedWorkoutPayload {
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

        let (exercises, equipment) = referencedCatalog(for: workout)
        return SharedWorkoutPayload(
            formatVersion: SharedWorkoutPayload.currentVersion,
            workout: dto,
            exercises: exercises,
            equipment: equipment
        )
    }

    /// Every catalog row this workout touches, deduplicated.
    ///
    /// All three section shapes have to be walked — `.time` steps, `.rep` exercises, and
    /// the `.emom`/`.amrap` quick entries. Missing any one of them would publish a
    /// workout whose recipient can't resolve part of it.
    private static func referencedCatalog(
        for workout: Workout
    ) -> ([ArchiveExercise], [ArchiveEquipment]) {
        var exercisesByID: [UUID: Exercise] = [:]
        var equipmentByID: [UUID: Equipment] = [:]

        for section in workout.sortedSections {
            for step in section.sortedTimeSteps {
                if let exercise = step.exercise { exercisesByID[exercise.id] = exercise }
            }
            for entry in section.sortedRepExercises {
                if let exercise = entry.exercise { exercisesByID[exercise.id] = exercise }
                // The only route from a workout to Equipment.
                if let equipment = entry.preferredEquipment { equipmentByID[equipment.id] = equipment }
            }
            for entry in section.sortedQuickExercises {
                if let exercise = entry.exercise { exercisesByID[exercise.id] = exercise }
            }
        }

        let exercises = exercisesByID.values
            .sorted { $0.name < $1.name }
            .map(exerciseOut)
        let equipment = equipmentByID.values
            .sorted { $0.name < $1.name }
            .map(equipmentOut)
        return (exercises, equipment)
    }

    /// Deliberately omits `generatedImageFileName`: the bytes live in this device's
    /// Application Support and don't travel with the payload, so carrying the filename
    /// would give the recipient a reference to a file they don't have.
    private static func exerciseOut(_ exercise: Exercise) -> ArchiveExercise {
        ArchiveExercise(
            id: exercise.id,
            name: exercise.name,
            label: exercise.label,
            notes: exercise.notes,
            videoURL: exercise.videoURL,
            iconSymbolName: exercise.iconSymbolName,
            // An asset-catalog name is compiled into every copy of the app, so this one
            // *does* resolve on the recipient's device.
            imageAssetName: exercise.imageAssetName,
            generatedImageFileName: nil,
            generatedImageStyle: nil,
            isCustom: exercise.isCustom,
            isFavorited: false,
            allowsBodyweight: exercise.allowsBodyweight,
            isOneSided: exercise.isOneSided,
            defaultEquipmentName: exercise.defaultEquipmentName,
            // Relationship ids are the publisher's and mean nothing to the recipient,
            // who resolves by name instead. Sent empty rather than misleadingly full.
            equipmentIDs: [],
            muscleIDs: [],
            categoryIDs: [],
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
}
