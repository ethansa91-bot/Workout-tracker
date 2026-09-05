import Foundation

/// Which form a set's weight control takes, decided by what the exercise is loaded
/// with. Shared by `SetRowView` and `HoldSetRowView` — a max-hold set can be loaded
/// too, so both rows offer the same three shapes.
enum SetWeightMode {
    /// A loaded set: +/- steps the equipment's preset combos, and the value itself is
    /// tappable for a weight that has no preset. There is no separate "manual" mode —
    /// typing a weight doesn't change what it was performed on.
    case stepper
    /// Nothing loaded: a fixed "Bodyweight" readout, weight logs as 0.
    case bodyweight
}

/// One step up or down the weight ladder, shared so both set rows behave identically.
///
/// Stepping below the lightest preset lands on bodyweight when the exercise allows it,
/// and stepping back up leaves it again. With no presets attached it falls back to 5-unit
/// increments, and a weight that matches no preset snaps to one end of the ladder.
func steppedSetWeight(
    delta: Int,
    weight: Double,
    isBodyweight: Bool,
    options: [WeightCombo],
    allowsBodyweight: Bool
) -> (weight: Double, isBodyweight: Bool) {
    if isBodyweight {
        guard delta > 0 else { return (weight, true) }
        return (options.first?.value ?? 0, false)
    }

    guard !options.isEmpty else {
        let stepped = weight + Double(delta) * 5
        if allowsBodyweight && stepped < 0 { return (0, true) }
        return (max(0, stepped), false)
    }

    guard let currentIndex = options.firstIndex(where: { $0.value == weight }) else {
        return (options[delta > 0 ? 0 : options.count - 1].value, false)
    }

    let newIndex = currentIndex + delta
    if allowsBodyweight && newIndex < 0 { return (0, true) }
    return (options[min(max(newIndex, 0), options.count - 1)].value, false)
}

/// "20 lb" / "22.5 kg" — trailing `.0` trimmed, since preset weights are usually whole.
func formattedSetWeight(_ value: Double, unit: String) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
}

/// The option matching `value` on this equipment's ladder — "3. Red", or "opt. 3" for
/// an option with no name.
///
/// A thin wrapper over `WeightCombo.optionDisplayName(for:in:)` so the set rows read the
/// same as the other two helpers here; the resolution itself lives on the model, where
/// records and history reach it too.
func formattedSetOption(_ value: Double, options: [WeightCombo]) -> String {
    WeightCombo.optionDisplayName(for: value, in: options)
}

/// Converts between kg and lb for *comparison* only — nothing in this app displays a
/// weight in anything but the unit it was actually stamped with.
///
/// Exists for the record page's "absolute record": the highest real weight for an
/// exercise across every equipment it's been recorded on, which is meaningless to
/// compare without a common unit first. Before this, no conversion existed anywhere in
/// the app — every weight was stored and shown verbatim in whatever unit it was set in.
enum WeightUnitConversion {
    private static let kgPerLb = 1 / 2.20462

    /// `value`, in kilograms, given the unit it's actually expressed in. Anything other
    /// than "lb" is treated as already kg — the app has exactly two real weight units,
    /// and a third string here (a level/option unit) should never reach this function;
    /// see `RecordVariant.absoluteComparisonWeightInKg`, its only caller, for the guard.
    static func kilograms(_ value: Double, unit: String) -> Double {
        unit == "lb" ? value * kgPerLb : value
    }
}
