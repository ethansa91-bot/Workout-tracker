import Foundation
import SwiftData

enum PersonalRecordQueries {
    /// The manually-saved record for one exercise on one equipment, of one shape — the
    /// lookup that matches how records are written, so it can't hand back a record of the
    /// wrong kind.
    ///
    /// Reps/weight and max-time are separate records: a plank's best hold has nothing to
    /// say about a weighted plank's best set, and promoting one over the other used to
    /// destroy it. Bodyweight is its own row again, with no equipment attached — which bar
    /// or rings it was done on doesn't change an unloaded achievement.
    static func current(
        for exercise: Exercise,
        equipment: Equipment?,
        trackingMode: RepExerciseTrackingMode,
        isBodyweight: Bool,
        context: ModelContext
    ) -> PersonalRecord? {
        let exerciseID = exercise.id
        // Filtered in Swift rather than in the predicate: `trackingMode` is a computed
        // wrapper over `trackingModeRaw`, and optional relationship ids don't compare
        // against a nil literal inside `#Predicate`.
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.deletedAt == nil }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let equipmentID = isBodyweight ? nil : equipment?.id
        return records
            .filter {
                $0.isBodyweight == isBodyweight
                    && $0.trackingMode == trackingMode
                    && (($0.isBodyweight ? nil : $0.equipment?.id) == equipmentID)
            }
            // Newest wins when sync has produced a duplicate, the same rule the Records
            // list applies — an arbitrary `.first` would flicker between them.
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// Whether a result beats the standing record.
    ///
    /// Heavier wins; at equal weight more reps wins; a longer hold wins. Same ranking
    /// `SetLogQueries.bestSetEver` already uses, so a record and a derived best agree
    /// about which of two sets is better.
    ///
    /// A record whose values are missing — or whose tracking mode doesn't match what was
    /// just performed — is treated as beaten, so the first result of a given shape always
    /// lands.
    static func beats(
        record: PersonalRecord?,
        trackingMode: RepExerciseTrackingMode,
        reps: Int?,
        weight: Double?,
        holdSeconds: Int?,
        isBodyweight: Bool
    ) -> Bool {
        guard let record else { return true }
        guard record.trackingMode == trackingMode, record.isBodyweight == isBodyweight else { return true }

        switch trackingMode {
        case .maxHoldTime:
            guard let holdSeconds else { return false }
            guard let best = record.holdSeconds else { return true }
            return holdSeconds > best

        case .repsWeight:
            guard let reps else { return false }
            // Bodyweight has no load to compare, so reps alone decide.
            if isBodyweight {
                guard let best = record.reps else { return true }
                return reps > best
            }
            guard let weight else { return false }
            guard let bestWeight = record.weight else { return true }
            if weight != bestWeight { return weight > bestWeight }
            return reps > (record.reps ?? 0)
        }
    }

    /// Files the record's current values into its history, then writes the new ones onto
    /// it — so the record always holds the current best and the entry holds what it beat.
    ///
    /// Creates the record when there isn't one. A record with no prior value files no
    /// history entry: there is nothing to supersede.
    @discardableResult
    static func setRecord(
        for exercise: Exercise,
        equipment: Equipment?,
        existing: PersonalRecord?,
        trackingMode: RepExerciseTrackingMode,
        reps: Int?,
        weight: Double?,
        holdSeconds: Int?,
        isBodyweight: Bool,
        weightUnit: String?,
        achievedAt: Date = .now,
        context: ModelContext
    ) -> PersonalRecord {
        let record: PersonalRecord
        if let existing {
            record = existing
            if hasValue(existing) {
                let previous = PersonalRecordEntry(
                    record: existing,
                    exercise: existing.exercise,
                    equipment: existing.equipment,
                    isBodyweight: existing.isBodyweight,
                    trackingMode: existing.trackingMode,
                    weight: existing.weight,
                    reps: existing.reps,
                    holdSeconds: existing.holdSeconds,
                    weightUnit: existing.weightUnit,
                    // The best available stamp for when the old value was set: records
                    // carry no achievement date of their own until this feature existed.
                    achievedAt: existing.updatedAt
                )
                context.insert(previous)
            }
        } else {
            record = PersonalRecord(exercise: exercise, equipment: equipment, isBodyweight: isBodyweight)
            context.insert(record)
        }

        record.exercise = exercise
        record.equipment = isBodyweight ? nil : equipment
        record.isBodyweight = isBodyweight
        record.trackingMode = trackingMode
        record.reps = reps
        record.weight = isBodyweight ? nil : weight
        record.holdSeconds = holdSeconds
        record.weightUnit = isBodyweight ? nil : weightUnit
        record.markDirty()
        try? context.save()
        return record
    }

    /// Whether a record holds anything worth keeping — a brand-new row created and saved
    /// in one go has nothing to file into history.
    private static func hasValue(_ record: PersonalRecord) -> Bool {
        record.reps != nil || record.weight != nil || record.holdSeconds != nil
    }
}
