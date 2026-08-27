import Foundation

/// Which form a set's weight control takes, decided by what the exercise is loaded
/// with. Shared by `SetRowView` and `HoldSetRowView` — a max-hold set can be loaded
/// too, so both rows offer the same three shapes.
enum SetWeightMode {
    /// +/- through the equipment's preset combos.
    case stepper
    /// A tappable value that opens the number pad — no presets to step through.
    case manual
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
