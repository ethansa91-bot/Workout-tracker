import Foundation
import SwiftData

/// Keyed by exercise, equipment *and* record shape. Deliberately not
/// `Dictionary(uniqueKeysWithValues:)`, which traps at runtime the moment two records
/// share a key — with per-equipment records that's an ordinary state, not a bug.
struct RecordVariantKey: Hashable {
    let exerciseID: UUID
    let equipmentID: UUID?
    /// Bodyweight is the load, so which bar or rings it was done on doesn't change the
    /// achievement — those keys always carry a nil `equipmentID`.
    let isBodyweight: Bool
    /// A plank's best hold and a weighted plank's best set are different records and
    /// must not share a slot: keyed without this, promoting one destroyed the other.
    let trackingMode: RepExerciseTrackingMode
    /// Always nil for an exercise that isn't splitting by type, so its whole history
    /// collapses onto one key exactly as it did before execution types existed.
    let executionTypeID: UUID?
    /// Always false for anything derived from a `SetLog`: only a Follow Along step
    /// produces one of these, and those log no weight to derive a best from.
    let isFollowAlong: Bool
}

/// One exercise's record on one equipment, of one shape. Several of these can belong to
/// the same exercise; both the Records list (grouped into one row) and the record page
/// (one collapsible section each) read the same list.
struct RecordVariant: Identifiable {
    let exercise: Exercise
    /// Which equipment this record belongs to — those lifts aren't comparable, so each
    /// keeps its own best.
    let equipment: Equipment?
    /// Weight/reps and max-time are separate achievements, so they're separate records
    /// rather than two readings of one.
    let trackingMode: RepExerciseTrackingMode
    /// nil is the general record, and stays its own row rather than being folded into a
    /// type — including on an exercise that now splits, where records set before the
    /// split are exactly the untyped ones.
    let executionType: ExecutionType?
    /// A Follow Along record is the load carried through a timed step, which is a
    /// different achievement from a best hold on the same equipment — so it is its own
    /// row rather than another reading of that one.
    let isFollowAlong: Bool

    /// Spelled out rather than left to the memberwise initializer. With ten parameters,
    /// five of them optional and three carrying defaults, resolving the synthesized one
    /// at the single call site below exceeds the type-checker's budget outright — no
    /// defaults means no overload set to search.
    init(
        exercise: Exercise,
        equipment: Equipment?,
        trackingMode: RepExerciseTrackingMode,
        record: PersonalRecord?,
        derivedBestSet: SetLogQueries.BestSet?,
        derivedHold: Int?,
        derivedBodyweightReps: Int?,
        isBodyweight: Bool,
        executionType: ExecutionType?,
        isFollowAlong: Bool
    ) {
        self.exercise = exercise
        self.equipment = equipment
        self.trackingMode = trackingMode
        self.record = record
        self.derivedBestSet = derivedBestSet
        self.derivedHold = derivedHold
        self.derivedBodyweightReps = derivedBodyweightReps
        self.isBodyweight = isBodyweight
        self.executionType = executionType
        self.isFollowAlong = isFollowAlong
    }
    let record: PersonalRecord?
    let derivedBestSet: SetLogQueries.BestSet?
    let derivedHold: Int?
    /// Best rep count achieved at body load. Bodyweight rows carry no equipment, so one
    /// exercise has exactly one of them however it was performed.
    let derivedBodyweightReps: Int?
    let isBodyweight: Bool
    /// Composed so two equipment rows for one exercise stay distinct — and so a
    /// bodyweight row never collides with the weighted row for the same exercise.
    var id: String {
        "\(exercise.id)-\(isBodyweight ? "bodyweight" : (equipment?.id.uuidString ?? "none"))-\(trackingMode.rawValue)-\(executionType?.id.uuidString ?? "any")-\(isFollowAlong ? "follow" : "rep")"
    }

    var key: RecordVariantKey {
        RecordVariantKey(
            exerciseID: exercise.id,
            equipmentID: isBodyweight ? nil : equipment?.id,
            isBodyweight: isBodyweight,
            trackingMode: trackingMode,
            executionTypeID: executionType?.id,
            isFollowAlong: isFollowAlong
        )
    }

    /// The catalog's own resolution when the variant names none — not the first weighted
    /// item in insertion order, which ignored `defaultEquipmentName` and so drew a
    /// different equipment's unit and setting colour than the builder and the runner
    /// resolve for the same exercise.
    var weightedEquipment: Equipment? {
        equipment ?? exercise.defaultWeightedEquipment
    }

    var currentWeightValue: Double? {
        record?.weight ?? derivedBestSet?.weight
    }

    /// Level-based equipment only — the matching level's color, if any, shown as a small
    /// dot next to the summary text.
    var settingColor: PaletteColor? {
        guard let equipment = weightedEquipment, equipment.usesOptions, let value = currentWeightValue else { return nil }
        return equipment.sortedWeightCombos.first(where: { $0.value == value })?.color
    }

    /// What the equipment line of the record page will read, so this row and that page
    /// name the same thing.
    var sourceLabel: String {
        PersonalRecordFormatting.sourceLabel(
            equipment: equipment,
            executionType: executionType,
            isBodyweight: isBodyweight,
            isFollowAlong: isFollowAlong
        )
    }

    /// The header the record page's own collapsible section reads — a different field
    /// order from `sourceLabel`, leading with what kind of record this is rather than
    /// trailing with it, and never used by the Records list.
    var headerLabel: String {
        PersonalRecordFormatting.variantHeaderLabel(
            trackingMode: trackingMode,
            equipment: equipment,
            executionType: executionType,
            isBodyweight: isBodyweight,
            isFollowAlong: isFollowAlong
        )
    }

    var summary: String {
        // Saved records go through the shared formatter so this list, the record page's
        // history and the in-workout popup can't word the same record differently.
        // Derived bests have no record to hand it.
        if let record { return PersonalRecordFormatting.summary(record) }
        switch trackingMode {
        case .maxHoldTime:
            guard let derivedHold else { return "" }
            return "\(derivedHold)s"
        case .repsWeight:
            // No load to state — the achievement is the rep count. Same phrasing the rep
            // runner uses for a logged bodyweight set.
            if isBodyweight {
                guard let derivedBodyweightReps else { return "" }
                return "\(derivedBodyweightReps) × Bodyweight"
            }
            guard let derivedBestSet else { return "" }
            return "\(formattedWeight(derivedBestSet.weight)) × \(derivedBestSet.reps)"
        }
    }

    private func formattedWeight(_ value: Double) -> String {
        PersonalRecordFormatting.weight(
            value,
            unit: weightedEquipment?.effectiveWeightUnit,
            equipment: weightedEquipment
        )
    }

    /// The value this variant would compare at for the "absolute record" — converted to
    /// kilograms so different equipment's units don't decide the winner. nil for
    /// anything that isn't a real, comparable weight: bodyweight has no load,
    /// option-based equipment's number is a rung on a ladder rather than a weight, and a
    /// Follow Along record is a load carried through a plan rather than a performance to
    /// rank — see `WeightUnitConversion`.
    var absoluteComparisonWeightInKg: Double? {
        guard !isBodyweight, !isFollowAlong, let equipment = weightedEquipment, !equipment.usesOptions,
              let value = currentWeightValue
        else { return nil }
        return WeightUnitConversion.kilograms(value, unit: equipment.effectiveWeightUnit)
    }
}

/// Builds the record variants for the exercises given — either the whole catalog (the
/// Records list) or a single exercise (the record page), the same aggregation either way
/// so the two screens can never disagree about what a variant is.
enum PersonalRecordVariants {
    static func build(exercises: [Exercise], records: [PersonalRecord], setLogs: [SetLog]) -> [RecordVariant] {
        let exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // One lookup, consulted by both passes below: whether an exercise keeps its
        // records apart by execution type decides whether the type belongs in its keys
        // at all, and the two passes must agree or a record and its derived best land on
        // different rows.
        let splitsByExercise = exercisesByID.mapValues(\.splitsRecordsByExecutionType)

        var recordsByKey: [RecordVariantKey: PersonalRecord] = [:]
        for record in records {
            guard let exerciseID = record.exercise?.id else { continue }
            let key = RecordVariantKey(
                exerciseID: exerciseID,
                equipmentID: record.isBodyweight ? nil : record.equipment?.id,
                isBodyweight: record.isBodyweight,
                trackingMode: record.trackingMode,
                // A typed record on an exercise that has since stopped splitting still
                // shows as its own row: the record genuinely belongs to that type, and
                // silently merging it with the untyped one would misreport both.
                executionTypeID: record.executionType?.id,
                isFollowAlong: record.isFollowAlong
            )
            // Newest wins if duplicates ever appear, rather than crashing.
            if let existing = recordsByKey[key], existing.updatedAt >= record.updatedAt { continue }
            recordsByKey[key] = record
        }

        var bestSetByKey: [RecordVariantKey: SetLogQueries.BestSet] = [:]
        var bestHoldByKey: [RecordVariantKey: Int] = [:]
        var bestBodyweightRepsByKey: [RecordVariantKey: Int] = [:]
        for log in setLogs {
            guard let exerciseID = log.exercise?.id else { continue }
            let isBodyweight = log.isBodyweight == true
            // A loaded set that records no equipment can't be attributed to one, and an
            // un-attributable set is not a record — it would file under a null equipment
            // this screen keys apart from the real one, showing as a phantom "No
            // equipment" copy beside it.
            if !isBodyweight, log.equipment == nil,
               exercisesByID[exerciseID]?.weightedEquipmentOptions.isEmpty == false {
                continue
            }
            // A bodyweight set still records whichever equipment was selected, but that
            // isn't what the record is about — drop it so every bodyweight set for an
            // exercise lands on one key rather than splitting per bar/rings.
            let equipmentID = isBodyweight ? nil : log.equipment?.id
            // Every set carries its execution type, but it only splits history for an
            // exercise that asked for that — otherwise all of them collapse onto the one
            // untyped key, which is the behaviour before this feature existed.
            let executionTypeID = (splitsByExercise[exerciseID] ?? false) ? log.executionType?.id : nil
            if let hold = log.holdSeconds {
                let key = RecordVariantKey(exerciseID: exerciseID, equipmentID: equipmentID, isBodyweight: isBodyweight, trackingMode: .maxHoldTime, executionTypeID: executionTypeID, isFollowAlong: false)
                if hold > (bestHoldByKey[key] ?? -1) {
                    bestHoldByKey[key] = hold
                }
                continue
            }
            let key = RecordVariantKey(exerciseID: exerciseID, equipmentID: equipmentID, isBodyweight: isBodyweight, trackingMode: .repsWeight, executionTypeID: executionTypeID, isFollowAlong: false)
            if isBodyweight {
                // No load to compare — reps alone decide the best.
                if log.reps > (bestBodyweightRepsByKey[key] ?? -1) {
                    bestBodyweightRepsByKey[key] = log.reps
                }
            } else {
                let candidate = SetLogQueries.BestSet(weight: log.weight, reps: log.reps)
                let current = bestSetByKey[key]
                if current == nil || candidate.weight > current!.weight || (candidate.weight == current!.weight && candidate.reps > current!.reps) {
                    bestSetByKey[key] = candidate
                }
            }
        }

        let keys = Set(recordsByKey.keys)
            .union(bestSetByKey.keys)
            .union(bestHoldByKey.keys)
            .union(bestBodyweightRepsByKey.keys)

        return keys.compactMap { key -> RecordVariant? in
            guard let exercise = exercisesByID[key.exerciseID] else { return nil }
            // Attached first, then the record's own reference. Looking only in
            // `equipmentItems` meant a record holding a perfectly good reference
            // rendered as "No equipment" the moment that equipment was detached — or,
            // with two catalog rows sharing one name, depending on which of them
            // happened to be attached when the list was built.
            //
            // It does *not* fall back to the exercise's default. A record that
            // genuinely records no equipment is a problem, and naming it after some
            // equipment it was never set on hides the problem behind a plausible lie —
            // one that reads as a real record in the wrong unit.
            let equipment = key.equipmentID.flatMap { id in
                exercise.equipmentItems.first { $0.id == id }
                    ?? recordsByKey[key]?.equipment
            }
            // Resolved off the record itself when the exercise no longer lists the
            // type, so a detached type still names the row it belongs to.
            var executionType: ExecutionType?
            if let typeID = key.executionTypeID {
                let attached: [ExecutionType] = exercise.sortedExecutionTypes
                executionType = attached.first { $0.id == typeID } ?? recordsByKey[key]?.executionType
            }
            let resolvedEquipment: Equipment? = key.isBodyweight ? nil : equipment
            let savedRecord: PersonalRecord? = recordsByKey[key]
            let bestSet: SetLogQueries.BestSet? = bestSetByKey[key]
            let bestHold: Int? = bestHoldByKey[key]
            let bestBodyweight: Int? = bestBodyweightRepsByKey[key]
            let followAlong: Bool = key.isFollowAlong
            return RecordVariant(
                exercise: exercise,
                equipment: resolvedEquipment,
                trackingMode: key.trackingMode,
                record: savedRecord,
                derivedBestSet: bestSet,
                derivedHold: bestHold,
                derivedBodyweightReps: bestBodyweight,
                isBodyweight: key.isBodyweight,
                executionType: executionType,
                isFollowAlong: followAlong
            )
        }
        .sorted {
            $0.exercise.name == $1.exercise.name
                ? ($0.equipment?.name ?? "") < ($1.equipment?.name ?? "")
                : $0.exercise.name < $1.exercise.name
        }
    }

    /// One exercise's variants, fetched and grouped on demand — what the record page
    /// opens with. Mirrors `PersonalRecordQueries.current`'s own exercise-scoped fetch
    /// rather than reading a `@Query` over every record in the store, since this is a
    /// pushed page rather than a list that benefits from `@Query`'s live diffing.
    static func variants(for exercise: Exercise, context: ModelContext) -> [RecordVariant] {
        let exerciseID = exercise.id
        let recordsDescriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.deletedAt == nil }
        )
        var setLogsDescriptor = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.isCancelled == false }
        )
        setLogsDescriptor.relationshipKeyPathsForPrefetching = [\.exercise, \.equipment]
        let records = (try? context.fetch(recordsDescriptor)) ?? []
        let setLogs = (try? context.fetch(setLogsDescriptor)) ?? []
        return build(exercises: [exercise], records: records, setLogs: setLogs)
    }
}
