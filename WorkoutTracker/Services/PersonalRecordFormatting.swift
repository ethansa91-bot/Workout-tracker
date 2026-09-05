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
        equipment: Equipment?,
        isFollowAlong: Bool = false
    ) -> String {
        // The step's duration is the plan's, not the achievement's — the load is the whole
        // record, so it is the whole line.
        if isFollowAlong {
            return self.weight(weight ?? 0, unit: weightUnit, equipment: equipment)
        }
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
        // A section record shares the storage but none of the facets below — no weight,
        // no equipment, no tracking mode. Routed off first so it can't be read as
        // "0 kg × 21".
        if record.isSectionRecord { return sectionSummary(record.reps) }
        return summary(
            isBodyweight: record.isBodyweight,
            trackingMode: record.trackingMode,
            weight: record.weight,
            reps: record.reps,
            holdSeconds: record.holdSeconds,
            weightUnit: record.weightUnit,
            equipment: record.equipment,
            isFollowAlong: record.isFollowAlong
        )
    }

    /// Resolved against the entry's *own* equipment, not whatever is selected on screen —
    /// a level name means nothing once you're looking at a different piece of kit.
    static func summary(_ entry: PersonalRecordEntry) -> String {
        if entry.isSectionRecord { return sectionSummary(entry.reps) }
        return summary(
            isBodyweight: entry.isBodyweight,
            trackingMode: entry.trackingMode,
            weight: entry.weight,
            reps: entry.reps,
            holdSeconds: entry.holdSeconds,
            weightUnit: entry.weightUnit,
            equipment: entry.equipment,
            isFollowAlong: entry.isFollowAlong
        )
    }

    /// A section record's value: "21 rounds".
    ///
    /// Both kinds read as rounds. That is already what the AMRAP runner's own counter
    /// says ("rounds — tap to count") and what a to-failure EMOM counts, so the record
    /// and the screen it came from use the same word.
    static func sectionSummary(_ value: Int?) -> String {
        let rounds = value ?? 0
        return "\(rounds) round\(rounds == 1 ? "" : "s")"
    }

    /// What a section record's row is called: its name, then the kind — "Cindy · EMOM".
    /// The section-record counterpart to `sourceLabel`.
    static func sectionSourceLabel(name: String?, kind: WorkoutSectionType?) -> String {
        let resolved = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let title = resolved ?? kind?.fallbackSectionName ?? "Section"
        guard let kind else { return title }
        return "\(title) · \(kind.pillLabel)"
    }

    /// What a record's *combination* is called: "Barbell", "Barbell · Explosive",
    /// "Bodyweight". The counterpart to `summary`, which names its value.
    ///
    /// Shared so the Records list's subtitle and the record page's "Records available" row
    /// can't word the same combination differently — the mistake `summary` was extracted to
    /// fix, one level up.
    static func sourceLabel(
        equipment: Equipment?,
        executionType: ExecutionType?,
        isBodyweight: Bool,
        isFollowAlong: Bool = false
    ) -> String {
        var base = isBodyweight ? "Bodyweight" : (equipment?.name ?? "No equipment")
        if let executionType {
            base += " · \(executionType.name)"
        }
        // Named, because the same equipment and type can hold both a rep record and a
        // Follow Along one and the Records list shows them as sibling rows.
        guard isFollowAlong else { return base }
        return "\(base) · Follow Along"
    }

    static func sourceLabel(_ record: PersonalRecord) -> String {
        sourceLabel(
            equipment: record.equipment,
            executionType: record.executionType,
            isBodyweight: record.isBodyweight,
            isFollowAlong: record.isFollowAlong
        )
    }

    /// The record page's own section header — a different field order from
    /// `sourceLabel`, leading with *what kind* of record this is (Follow Along, then
    /// weight/reps vs. max time) before naming what it was set on. `sourceLabel` keeps
    /// its existing order for its own callers (the Records list, `SavedCombination`);
    /// this is deliberately a second function rather than a change to that one.
    static func variantHeaderLabel(
        trackingMode: RepExerciseTrackingMode,
        equipment: Equipment?,
        executionType: ExecutionType?,
        isBodyweight: Bool,
        isFollowAlong: Bool
    ) -> String {
        var parts: [String] = []
        if isFollowAlong {
            // Neither label fits: a Follow Along record is a load carried through a
            // timed step, not a rep set and not a held-for-time achievement. It's
            // stamped `.maxHoldTime` internally (see `FollowAlongRecordCard`, a leftover
            // from before `isFollowAlong` was its own dimension), so `trackingMode` can't
            // be trusted here the way `summary()` already knows not to trust it either —
            // "Follow Along" alone already says what kind of record this is.
            parts.append("Follow Along")
        } else {
            parts.append(trackingMode == .maxHoldTime ? "Max Time" : "Weight & Reps")
        }
        parts.append(isBodyweight ? "Bodyweight" : (equipment?.name ?? "No equipment"))
        if let executionType { parts.append(executionType.name) }
        return parts.joined(separator: " · ")
    }

    /// Option-based equipment names the matching option, everything else "value unit".
    /// A nil unit falls back to the global preference, which is what a record saved
    /// before units were stamped has.
    static func weight(_ value: Double, unit: String?, equipment: Equipment?) -> String {
        if let equipment, equipment.usesOptions {
            return WeightCombo.optionDisplayName(for: value, in: equipment.sortedWeightCombos)
        }
        // The equipment is gone but the record still carries the unit it was set in, and
        // `Equipment.optionUnit` is a storage token — printing it gives "3 level".
        if unit == Equipment.optionUnit {
            return WeightCombo.optionDisplayName(for: value)
        }
        return formattedSetWeight(value, unit: unit ?? AppSettings.weightUnit)
    }
}
