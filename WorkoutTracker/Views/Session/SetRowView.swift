import SwiftUI

/// One set: pending (editable draft, +/- steps through the equipment's weight combos
/// and reps one at a time) or logged (read-only with a Cancel action).
///
/// Two shapes. The compact default is a single row, used for the recap of completed
/// sets. `isProminent` is the focused form the session runner shows for the set being
/// worked on right now: same steppers, but scaled up with a full-width Save button
/// underneath, sized to be hit without looking.
struct SetRowView: View {
    /// How the weight is entered for this set.
    enum WeightMode {
        /// +/- through the equipment's preset combos.
        case stepper
        /// A tappable value that opens the number pad — no presets to step through.
        case manual
        /// Nothing loaded: a fixed "Bodyweight" readout, weight logs as 0.
        case bodyweight
    }

    let setNumber: Int
    /// "Left"/"Right" for one-sided exercises tracked per side; nil otherwise.
    var sideLabel: String? = nil
    var weightMode: WeightMode = .stepper
    let weightOptions: [WeightCombo]
    let weightUnit: String
    @Binding var reps: Int
    @Binding var weight: Double
    /// Whether this set is being performed unloaded. Stepping down past the lightest
    /// weight lands here; stepping back up leaves it. Only reachable when
    /// `allowsBodyweight` — otherwise it stays false and the stepper behaves as before.
    @Binding var isBodyweight: Bool
    let isLogged: Bool
    let isWorseThanLast: Bool
    var isProminent: Bool = false
    var allowsBodyweight: Bool = false
    /// Off when the row is one of a pair sharing a single Save below them — see the
    /// side-tracked card in `RepSessionRunnerView`.
    var showsSaveButton: Bool = true
    /// True for the moment after a save: Save is held disabled while the caller
    /// highlights what changed.
    var isSaving: Bool = false
    let onLog: () -> Void
    let onCancel: () -> Void

    @State private var showingWheel = false

    private var isLevelBased: Bool { weightUnit == Equipment.levelUnit }

    private static let actionButtonCornerRadius: CGFloat = 12
    /// Gutter reserved for "Left"/"Right" in the prominent card.
    private static let sideLabelWidth: CGFloat = 48

    var body: some View {
        if isProminent {
            prominentBody
        } else {
            compactBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 12) {
            if isWorseThanLast {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Set \(setNumber)")
                    .font(.subheadline.weight(.medium))
                if let sideLabel {
                    Text(sideLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, alignment: .leading)

            // Spread across the middle: the set number stays hard left and the button
            // hard right, so every recap row reads on the same columns.
            weightStepper
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("×").foregroundStyle(.secondary)
            repsStepper
                .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer(minLength: 12)

            if isLogged {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.appDanger)
            } else {
                Button("Log", action: onLog)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .opacity(isLogged ? 0.7 : 1)
    }

    private var prominentBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                // Fixed width, so the controls start at the same x on both rows and the
                // longer "Right" doesn't shove its steppers out of line with "Left".
                if sideLabel != nil {
                    Text(sideLabel ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: Self.sideLabelWidth, alignment: .leading)
                }

                // Each control takes half the row but stays left-anchored inside it —
                // without the explicit alignment they'd centre in their own share and
                // drift away from the set title above.
                HStack(spacing: 8) {
                    weightStepper
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("×").foregroundStyle(.secondary)
                    // Trailing-aligned so the "×" sits mid-row between the two controls
                    // rather than drifting left with the reps.
                    repsStepper
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.title3)

            if showsSaveButton {
                // The fill goes on the label, not the Button: applying it outside only
                // widens the button's frame while the title stays at its intrinsic size,
                // which reads as a centered button in a full-width box.
                Button(action: onLog) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // `.large` bakes in ~20pt of its own vertical padding, so no amount of
                // trimming the label shrinks it — the control size is the actual lever.
                .controlSize(.regular)
                .buttonBorderShape(.roundedRectangle(radius: Self.actionButtonCornerRadius))
                .disabled(isSaving)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The weight control, in whichever form this set's source calls for: +/- presets,
    /// a tap-to-type field, or a fixed bodyweight readout with no control at all.
    @ViewBuilder
    private var weightStepper: some View {
        switch weightMode {
        case .stepper:
            if isLogged {
                // A saved set is a record, not a control — the +/- would be inert.
                weightDisplay
                    .frame(minWidth: weightFieldWidth, alignment: .center)
            } else {
                HStack(spacing: isProminent ? (sideLabel == nil ? 12 : 8) : 4) {
                    Button {
                        stepWeight(delta: -1)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    weightDisplay
                        .frame(minWidth: weightFieldWidth, alignment: .center)
                    Button {
                        stepWeight(delta: 1)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        case .manual:
            manualWeightControl
        case .bodyweight:
            Text("Bodyweight")
                .font(valueFont)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(minWidth: weightFieldWidth)
        }
    }

    /// Tapping the value opens a scrolling wheel. Logged sets show it plainly — a
    /// recorded set isn't editable in place.
    @ViewBuilder
    private var manualWeightControl: some View {
        if isLogged {
            Text(formattedWeight(weight))
                .font(valueFont)
                .frame(minWidth: weightFieldWidth)
        } else {
            Button {
                showingWheel = true
            } label: {
                HStack(spacing: 4) {
                    Text(formattedWeight(weight))
                        .font(valueFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: weightFieldWidth)
                .padding(.vertical, isProminent ? 6 : 2)
                .padding(.horizontal, 8)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.appHairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingWheel) {
                weightWheelSheet
            }
        }
    }

    private var weightWheelSheet: some View {
        NavigationStack {
            VStack {
                WeightWheelPicker(value: $weight, unit: weightUnit)
                    .padding()
                Spacer()
            }
            .background(Color.appBackground)
            .navigationTitle(sideLabel.map { "Set \(setNumber) · \($0)" } ?? "Set \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingWheel = false }
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    /// "Bodyweight" needs far more room than a number, and a stepper whose width jumps
    /// as you step onto it reads as a glitch — so the space is reserved up front. When a
    /// side label shares the row there's less to go around, so the reservation shrinks
    /// and the text scales instead.
    private var weightFieldWidth: CGFloat {
        guard isProminent else { return allowsBodyweight ? 92 : 60 }
        if sideLabel != nil { return allowsBodyweight ? 104 : 78 }
        return allowsBodyweight ? 130 : 92
    }

    /// Level-based equipment shows the matching combo's color dot + label (falling
    /// back to "Level N"); everything else shows the plain numeric "value unit" text
    /// as before.
    @ViewBuilder
    private var weightDisplay: some View {
        if isBodyweight {
            Text("Bodyweight")
                .font(valueFont)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if isLevelBased, let combo = weightOptions.first(where: { $0.value == weight }) {
            HStack(spacing: 4) {
                if let color = combo.color {
                    Circle().fill(color.color).frame(width: 8, height: 8)
                }
                Text(combo.levelDisplayName)
                    .font(valueFont)
                    .lineLimit(1)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(weightNumberText(weight))
                    .font(valueFont)
                Text(weightUnit)
                    .font(unitFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The unit reads as a unit — same muted caption as "reps" — instead of sharing the
    /// number's display size.
    private var unitFont: Font {
        isProminent ? .caption : .caption2
    }

    private func weightNumberText(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    @ViewBuilder
    private var repsStepper: some View {
        if isLogged {
            repsValue
        } else {
            HStack(spacing: isProminent ? (sideLabel == nil ? 12 : 8) : 4) {
                Button {
                    if reps > 0 { reps -= 1 }
                } label: {
                    Image(systemName: "minus.circle")
                }
                repsValue
                Button {
                    reps += 1
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
    }

    /// The count with its own unit, so it reads the same way the weight does ("55 kg",
    /// "8 reps") rather than as a bare number.
    private var repsValue: some View {
        // Width on the pair, centered — so "9 reps" sits midway between the − and +
        // rather than hugging one side, and the buttons don't shift as digits change.
        // Baseline-aligned, not centered: a small unit centered against a big number
        // floats mid-height instead of sitting on the same line as it.
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(reps)")
                .font(valueFont)
            Text("reps")
                .font(unitFont)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: isProminent ? (sideLabel == nil ? 76 : 64) : 48, alignment: .center)
    }

    private var valueFont: Font {
        isProminent ? .title2.monospacedDigit().weight(.medium) : .subheadline.monospacedDigit()
    }

    /// "Bodyweight" sits one position below the lightest weight, so the range is walked
    /// with the same two buttons: stepping down off the bottom enters it, stepping up
    /// leaves it for the lightest option.
    private func stepWeight(delta: Int) {
        if isBodyweight {
            guard delta > 0 else { return }
            isBodyweight = false
            weight = weightOptions.first?.value ?? 0
            return
        }

        guard !weightOptions.isEmpty else {
            let stepped = weight + Double(delta) * 5
            if allowsBodyweight && stepped < 0 {
                isBodyweight = true
                weight = 0
            } else {
                weight = max(0, stepped)
            }
            return
        }

        guard let currentIndex = weightOptions.firstIndex(where: { $0.value == weight }) else {
            weight = weightOptions[delta > 0 ? 0 : weightOptions.count - 1].value
            return
        }

        let newIndex = currentIndex + delta
        if allowsBodyweight && newIndex < 0 {
            isBodyweight = true
            weight = 0
            return
        }
        weight = weightOptions[min(max(newIndex, 0), weightOptions.count - 1)].value
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(weightUnit)" : "\(value) \(weightUnit)"
    }
}
