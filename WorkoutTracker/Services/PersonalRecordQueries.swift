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
    ///
    /// `executionType` is the fourth facet, and the only optional one: pass the type only
    /// when the exercise is actually splitting by it (`resolvedExecutionType` does that
    /// check), and nil otherwise, so an exercise that isn't splitting keeps resolving to
    /// the one untyped record it always had.
    static func current(
        for exercise: Exercise,
        equipment: Equipment?,
        executionType: ExecutionType? = nil,
        trackingMode: RepExerciseTrackingMode,
        isBodyweight: Bool,
        isFollowAlong: Bool = false,
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
        let executionTypeID = executionType?.id
        return records
            .filter {
                $0.isBodyweight == isBodyweight
                    && $0.isFollowAlong == isFollowAlong
                    && $0.trackingMode == trackingMode
                    && (($0.isBodyweight ? nil : $0.equipment?.id) == equipmentID)
                    && $0.executionType?.id == executionTypeID
            }
            // Newest wins when sync has produced a duplicate, the same rule the Records
            // list applies — an arbitrary `.first` would flicker between them.
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// One saved record, reduced to what a picker needs: how to name it, and the selection
    /// that reopens it.
    struct SavedCombination: Identifiable {
        let id: UUID
        let equipment: Equipment?
        let executionType: ExecutionType?
        let isBodyweight: Bool
        let isFollowAlong: Bool
        let trackingMode: RepExerciseTrackingMode
        /// "Barbell · Explosive"
        let label: String
        /// "100 kg × 5"
        let value: String
    }

    /// Every combination this exercise already holds a *saved* record for, newest-wins on
    /// a sync duplicate and ordered the way the Records list orders its variants.
    ///
    /// Derived bests are deliberately excluded: they are values the app inferred from
    /// logged sets, and offering one here would suggest a record exists where none was set.
    static func savedCombinations(for exercise: Exercise, context: ModelContext) -> [SavedCombination] {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.deletedAt == nil }
        )
        let records = (try? context.fetch(descriptor)) ?? []

        // A record with nothing in it is a row the editor created and never saved a value
        // to — listing it would offer a record that reads blank.
        var newestByKey: [String: PersonalRecord] = [:]
        for record in records where record.reps != nil || record.weight != nil || record.holdSeconds != nil {
            let key = [
                record.isBodyweight ? "bw" : (record.equipment?.id.uuidString ?? "none"),
                record.executionType?.id.uuidString ?? "any",
                record.trackingModeRaw,
                record.isFollowAlong ? "follow" : "rep"
            ].joined(separator: "|")
            if let existing = newestByKey[key], existing.updatedAt >= record.updatedAt { continue }
            newestByKey[key] = record
        }

        return newestByKey.values
            .map { record in
                SavedCombination(
                    id: record.id,
                    equipment: record.equipment,
                    executionType: record.executionType,
                    isBodyweight: record.isBodyweight,
                    isFollowAlong: record.isFollowAlong,
                    trackingMode: record.trackingMode,
                    label: PersonalRecordFormatting.sourceLabel(record),
                    value: PersonalRecordFormatting.summary(record)
                )
            }
            // Same order the Records list sorts its variants in: bodyweight first, then by
            // equipment, then reps/weight before max-time, then untyped before typed.
            .sorted { lhs, rhs in
                if lhs.isBodyweight != rhs.isBodyweight { return lhs.isBodyweight }
                if lhs.equipment?.name != rhs.equipment?.name {
                    return (lhs.equipment?.name ?? "") < (rhs.equipment?.name ?? "")
                }
                if lhs.trackingMode != rhs.trackingMode { return lhs.trackingMode == .repsWeight }
                let lhsHasType = lhs.executionType != nil
                let rhsHasType = rhs.executionType != nil
                if lhsHasType != rhsHasType { return !lhsHasType }
                return (lhs.executionType?.name ?? "") < (rhs.executionType?.name ?? "")
            }
    }

    /// Which execution type a record lookup should be scoped to, given what was actually
    /// performed. The single place the "separate records per type" rule is applied, so the
    /// runner, the records list and the record editor can't disagree about it.
    ///
    /// nil whenever the exercise isn't splitting — everything then files into the untyped
    /// record exactly as it did before execution types existed, which is what keeps
    /// turning the toggle on from stranding or rewriting any record already set.
    static func resolvedExecutionType(_ executionType: ExecutionType?, for exercise: Exercise) -> ExecutionType? {
        exercise.splitsRecordsByExecutionType ? executionType : nil
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
        isBodyweight: Bool,
        isFollowAlong: Bool = false
    ) -> Bool {
        guard let record else { return true }
        guard record.trackingMode == trackingMode,
              record.isBodyweight == isBodyweight,
              record.isFollowAlong == isFollowAlong
        else { return true }

        // A Follow Along step runs for a fixed duration, so the load is the whole
        // achievement — the `.maxHoldTime` branch below compares seconds and would call
        // every weight a tie.
        if isFollowAlong {
            guard let weight else { return false }
            guard let best = record.weight else { return true }
            return weight > best
        }

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
        executionType: ExecutionType? = nil,
        existing: PersonalRecord?,
        trackingMode: RepExerciseTrackingMode,
        reps: Int?,
        weight: Double?,
        holdSeconds: Int?,
        isBodyweight: Bool,
        isFollowAlong: Bool = false,
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
                    executionType: existing.executionType,
                    isBodyweight: existing.isBodyweight,
                    isFollowAlong: existing.isFollowAlong,
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
            record = PersonalRecord(exercise: exercise, equipment: equipment, executionType: executionType, isBodyweight: isBodyweight, isFollowAlong: isFollowAlong)
            context.insert(record)
        }

        record.exercise = exercise
        record.equipment = isBodyweight ? nil : equipment
        // Not cleared for a bodyweight record the way equipment is: how a rep was
        // performed is still meaningful at body load, where which bar it was on isn't.
        record.executionType = executionType
        record.isBodyweight = isBodyweight
        record.isFollowAlong = isFollowAlong
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

    // MARK: - Section records

    /// The record for an EMOM/AMRAP section, keyed on the `recordGroupID` every copy of
    /// that section carries — so the same benchmark used in three workouts resolves to
    /// one record.
    ///
    /// Deliberately unrelated to `current(for:…)` above: a section record shares the
    /// storage but none of the facets, so folding the two lookups together would mean a
    /// signature where most parameters are meaningless to half the callers.
    static func sectionRecord(groupID: UUID, context: ModelContext) -> PersonalRecord? {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.sectionRecordGroupID == groupID && $0.deletedAt == nil }
        )
        // Newest wins when sync has produced a duplicate, the same rule every other
        // record lookup here applies.
        return ((try? context.fetch(descriptor)) ?? []).max { $0.updatedAt < $1.updatedAt }
    }

    /// More rounds wins. A record with no value yet is beaten by anything, including
    /// zero rounds — the first result set is always worth keeping.
    static func sectionBeats(record: PersonalRecord?, value: Int) -> Bool {
        guard let record, let best = record.reps else { return true }
        return value > best
    }

    /// The section-record twin of `setRecord`: files the standing value into history,
    /// then writes the new one. Creates the record when there isn't one.
    @discardableResult
    static func setSectionRecord(
        groupID: UUID,
        name: String,
        kind: WorkoutSectionType,
        value: Int,
        existing: PersonalRecord?,
        achievedAt: Date = .now,
        context: ModelContext
    ) -> PersonalRecord {
        let record: PersonalRecord
        if let existing {
            record = existing
            if existing.reps != nil {
                let previous = PersonalRecordEntry(
                    record: existing,
                    trackingMode: existing.trackingMode,
                    reps: existing.reps,
                    sectionRecordGroupID: existing.sectionRecordGroupID,
                    sectionRecordKind: existing.sectionRecordKind,
                    // The name as it was when that value was set, so a renamed section
                    // doesn't retroactively relabel its own past.
                    sectionRecordName: existing.sectionRecordName,
                    achievedAt: existing.updatedAt
                )
                context.insert(previous)
            }
        } else {
            record = PersonalRecord(
                sectionRecordGroupID: groupID,
                sectionRecordKind: kind,
                sectionRecordName: name
            )
            context.insert(record)
        }

        record.sectionRecordGroupID = groupID
        record.sectionRecordKind = kind
        record.sectionRecordName = name
        record.reps = value
        record.markDirty()
        try? context.save()
        return record
    }
}
