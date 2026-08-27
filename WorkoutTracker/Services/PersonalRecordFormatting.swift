import Foundation

/// Turns a record — or one of its superseded values — into the single line every screen
/// shows it as.
///
/// Extracted because three places render this and two of them disagreed: the Records list
/// wrote a loaded hold as "60s × 20 kg" while the record page's history wrote it
/// "20 kg × 60s". Weight leads everywhere now, so a record reads in the same order as the
/// set row that earns it.
enum PersonalRecordFormatting {
    /// "100 kg × 5" · "12 × Bodyweight" · "60s" · "20 kg × 60s"
    static func summary(
        isBodyweight: Bool,
        trackingMode: RepExerciseTrackingMode,
        weight: Double?,
        reps: Int?,
        holdSeconds: Int?,
        weightUnit: String?,
        equipment: Equipment?
    ) -> String {
        switch trackingMode {
        case .maxHoldTime:
            let hold = "\(holdSeconds ?? 0)s"
            // An unloaded hold reads as it always did; a weighted plank states its load.
            guard !isBodyweight, let weight, weight > 0 else { return hold }
            return "\(self.weight(weight, unit: weightUnit, equipment: equipment)) × \(hold)"
        case .repsWeight:
            // No load to state — the achievement is the rep count.
            if isBodyweight { return "\(reps ?? 0) × Bodyweight" }
            return "\(self.weight(weight ?? 0, unit: weightUnit, equipment: equipment)) × \(reps ?? 0)"
        }
    }

    static func summary(_ record: PersonalRecord) -> String {
        summary(
            isBodyweight: record.isBodyweight,
            trackingMode: record.trackingMode,
            weight: record.weight,
            reps: record.reps,
            holdSeconds: record.holdSeconds,
            weightUnit: record.weightUnit,
            equipment: record.equipment
        )
    }

    /// Resolved against the entry's *own* equipment, not whatever is selected on screen —
    /// a level name means nothing once you're looking at a different piece of kit.
    static func summary(_ entry: PersonalRecordEntry) -> String {
        summary(
            isBodyweight: entry.isBodyweight,
            trackingMode: entry.trackingMode,
            weight: entry.weight,
            reps: entry.reps,
            holdSeconds: entry.holdSeconds,
            weightUnit: entry.weightUnit,
            equipment: entry.equipment
        )
    }

    /// Level-based equipment shows the matching level's name, everything else "value unit".
    /// A nil unit falls back to the global setting, which is what a record saved before
    /// units were stamped has.
    static func weight(_ value: Double, unit: String?, equipment: Equipment?) -> String {
        if let equipment, equipment.isLevelBased {
            if let combo = equipment.sortedWeightCombos.first(where: { $0.value == value }) {
                return combo.levelDisplayName
            }
            return "Level \(Int(value))"
        }
        return formattedSetWeight(value, unit: unit ?? AppSettings.weightUnit)
    }
}
