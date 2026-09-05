import Foundation
import SwiftData

/// Attributes equipment to sets and records that were saved before the field existed.
///
/// `SetLog.equipment` and `PersonalRecord.equipment` both arrived in "redesign rep view"
/// (20 Aug) and nothing ever migrated what was already stored, so every set logged and
/// every record set before that date carries nil. The Records screen keys a nil-equipment
/// row apart from a real one, which is why a weighted exercise could show its record twice
/// — once properly and once as "No equipment".
///
/// Only where there is nothing to guess: an exercise with exactly one weighted equipment
/// was performed on that one. Two or more and the row is left alone — choosing between a
/// barbell and a dumbbell would invent history rather than recover it. Bodyweight rows are
/// skipped outright; nil is their correct value.
enum RecordEquipmentBackfill {
    private static let migratedFlagKey = "migration.recordEquipmentV1"

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        // One weighted option, or nothing to do — computed per exercise rather than per
        // row, since a popular exercise can carry hundreds of sets.
        var soleEquipment: [UUID: Equipment] = [:]
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
            let weighted = exercise.weightedEquipmentOptions
            guard weighted.count == 1, let only = weighted.first else { continue }
            soleEquipment[exercise.id] = only
        }
        guard !soleEquipment.isEmpty else { return }

        var didChange = false

        for log in (try? context.fetch(FetchDescriptor<SetLog>())) ?? [] {
            guard log.equipment == nil, log.isBodyweight != true,
                  let exerciseID = log.exercise?.id,
                  let equipment = soleEquipment[exerciseID]
            else { continue }
            log.equipment = equipment
            log.markDirty()
            didChange = true
        }

        for record in (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? [] {
            guard record.equipment == nil, !record.isBodyweight,
                  let exerciseID = record.exercise?.id,
                  let equipment = soleEquipment[exerciseID]
            else { continue }
            record.equipment = equipment
            record.markDirty()
            didChange = true
        }

        for entry in (try? context.fetch(FetchDescriptor<PersonalRecordEntry>())) ?? [] {
            guard entry.equipment == nil, !entry.isBodyweight,
                  let exerciseID = entry.exercise?.id,
                  let equipment = soleEquipment[exerciseID]
            else { continue }
            entry.equipment = equipment
            entry.markDirty()
            didChange = true
        }

        if didChange { try? context.save() }
    }
}
