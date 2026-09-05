import SwiftUI

/// One max-hold-time set: idle → (full-screen `HoldTimerOverlayView` runs the
/// head-start countdown and count-up) → stopped (correctable before confirming), or
/// logged (read-only with a Cancel action) — the stopwatch counterpart to
/// `SetRowView`'s reps/weight row.
struct HoldSetRowView: View {
    let setNumber: Int
    let exerciseName: String
    let headStartSeconds: Int
    /// The best hold ever recorded for this exercise (nil if there's no history yet).
    /// When the live count-up reaches it, a "reached your best" cue plays once.
    let previousBest: Int?
    @Binding var recordedSeconds: Int
    /// A hold can be loaded (a weighted plank, a weighted dead hang), so the row carries
    /// the same weight controls `SetRowView` does. `.bodyweight` hides them entirely,
    /// which is what an unloaded hold gets — and what every hold got before this.
    var weightMode: SetWeightMode = .bodyweight
    var weightOptions: [WeightCombo] = []
    var weightUnit: String = ""
    var weight: Binding<Double> = .constant(0)
    var isBodyweight: Binding<Bool> = .constant(true)
    var allowsBodyweight: Bool = false
    let isLogged: Bool
    /// See `SetRowView.isProminent` — the focused form for the set in progress.
    var isProminent: Bool = false
    /// True for the moment after a save, while the runner highlights the set number —
    /// the button stays disabled so the next set can't start mid-transition.
    var isSaving: Bool = false
    var onStart: () -> Void = {}
    let onLog: () -> Void
    let onCancel: () -> Void

    private enum Phase {
        case idle, stopped
    }

    @State private var phase: Phase = .idle
    @State private var showingOverlay = false
    @State private var showingWheel = false
    @State private var showingTimeWheel = false

    private static let actionButtonCornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if isProminent {
                prominentBody
            } else {
                compactBody
            }
        }
        .fullScreenCover(isPresented: $showingOverlay) {
            HoldTimerOverlayView(
                exerciseName: exerciseName,
                headStartSeconds: headStartSeconds,
                previousBest: previousBest
            ) { finalSeconds in
                recordedSeconds = finalSeconds
                phase = .stopped
            }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 12) {
            Text("Set \(setNumber)")
                .font(.subheadline.weight(.medium))
                .frame(width: 46, alignment: .leading)

            // Same columns as `SetRowView`'s recap — number hard left, load then value
            // across the middle, button hard right — so both tracking modes read alike.
            valueColumns

            Spacer(minLength: 12)

            trailingControl
        }
        .opacity(isLogged ? 0.7 : 1)
    }

    private var prominentBody: some View {
        VStack(spacing: 20) {
            valueColumns
                .font(.title3)
            prominentControl
        }
    }

    /// Load and time on one line, in the order `SetRowView` puts weight and reps — a
    /// weighted plank reads "22.5 kg × 60s", the same way its record does.
    ///
    /// The load and the time, side by side. Every hold has a load — body weight is one —
    /// so the left column is always there and the `×` always has something to join.
    @ViewBuilder
    private var valueColumns: some View {
        if isLogged || phase == .stopped {
            HStack(spacing: 8) {
                weightRow
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("×").foregroundStyle(.secondary)
                content
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            // Before the timer runs, `content` is a sentence of instructions rather than a
            // value — joining that to the load with a "×" reads as nonsense, so the two
            // keep the arrangement they had.
            if isProminent {
                VStack(alignment: .leading, spacing: 12) {
                    content
                    weightRow
                }
            } else {
                HStack(spacing: 12) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                    weightRow
                }
            }
        }
    }

    /// The load, always shown — a hold done at body weight is still done at *some* load,
    /// and rendering nothing made an unloaded hold look like it had lost a control. Reads
    /// exactly like `SetRowView`'s weight column, which is the row this one sits beside.
    ///
    /// No `scalemass` icon: `SetRowView` has none, and on the prominent stopped layout
    /// every point of width counts — see `weightFieldWidth`.
    @ViewBuilder
    private var weightRow: some View {
        HStack(spacing: isProminent ? 8 : 4) {
            switch weightMode {
            case .bodyweight:
                Text("Bodyweight")
                    .font(valueFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: weightFieldWidth, maxWidth: .infinity, alignment: .leading)
            case .stepper:
                if isLogged {
                    Text(weightLabel)
                        .font(valueFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: weightFieldWidth, alignment: .center)
                } else {
                    Button {
                        step(-1)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    // −/+ walk the equipment's ladder; the value opens the wheel, for
                    // a weight it has no preset for. The set still belongs to the
                    // chosen equipment either way. Option-based equipment has no weight
                    // to type — same plain label `SetRowView` shows.
                    if usesOptions {
                        Text(weightLabel)
                            .font(valueFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(minWidth: weightFieldWidth)
                    } else {
                        Button {
                            showingWheel = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(weightLabel)
                                    .font(valueFont)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minWidth: weightFieldWidth)
                            .padding(.vertical, isProminent ? 6 : 2)
                            .padding(.horizontal, 6)
                            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appHairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        step(1)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingWheel) {
            weightWheelSheet
        }
    }

    /// A floor, not a reservation — the same value and the same reasoning as
    /// `SetRowView.weightFieldWidth`, which this row was 20pt wider than.
    ///
    /// That extra width was a hard minimum propagated up through the card, and `.padding`
    /// doesn't clamp: on the prominent stopped layout the whole card, Save button
    /// included, was pushed off the right edge of an iPhone. The label scales down to meet
    /// this floor instead.
    ///
    /// Below `SetRowView`'s 72 because this row carries *two* three-part steppers either
    /// side of a `×`, where that one carries a stepper and a rep count. The budget on a
    /// 375pt screen is 311 — the screen less `compactBody`'s padding and the card's — and
    /// 72 here overran it by about 13.
    private var weightFieldWidth: CGFloat { isProminent ? 56 : 60 }

    private var weightLabel: String {
        if isBodyweight.wrappedValue { return "Bodyweight" }
        // Same readout `SetRowView` uses — a loaded hold steps the same ladder, so it
        // should name the option in the same words.
        return usesOptions
            ? formattedSetOption(weight.wrappedValue, options: weightOptions)
            : formattedSetWeight(weight.wrappedValue, unit: weightUnit)
    }

    private var usesOptions: Bool { weightUnit == Equipment.optionUnit }

    private func step(_ delta: Int) {
        let stepped = steppedSetWeight(
            delta: delta,
            weight: weight.wrappedValue,
            isBodyweight: isBodyweight.wrappedValue,
            options: weightOptions,
            allowsBodyweight: allowsBodyweight
        )
        weight.wrappedValue = stepped.weight
        isBodyweight.wrappedValue = stepped.isBodyweight
    }

    private var weightWheelSheet: some View {
        NavigationStack {
            VStack {
                WeightWheelPicker(value: weight, unit: weightUnit)
                    .padding()
                Spacer()
            }
            .background(Color.appBackground)
            .navigationTitle("Set \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingWheel = false }
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    /// The full-width counterpart to `trailingControl` — Start before the hold, Save
    /// after it, both at the same size so the button never moves under the thumb.
    /// Styled exactly like the reps/weight Save — fill on the label, `.regular` size —
    /// so the two tracking modes present the same control.
    @ViewBuilder
    private var prominentControl: some View {
        switch phase {
        case .idle:
            actionButton("Start recording") { start() }
        case .stopped:
            actionButton("Save", action: onLog)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .buttonBorderShape(.roundedRectangle(radius: Self.actionButtonCornerRadius))
        .disabled(isSaving)
    }

    @ViewBuilder
    private var content: some View {
        if isLogged {
            Text("\(recordedSeconds)s")
                .font(valueFont)
        } else {
            switch phase {
            case .idle:
                Text("Start recording to track maximum time rep")
                    .font(isProminent ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .stopped:
                stoppedStepper
            }
        }
    }

    private var stoppedStepper: some View {
        HStack(spacing: isProminent ? 8 : 4) {
            Button {
                if recordedSeconds > 0 { recordedSeconds -= 1 }
            } label: {
                Image(systemName: "minus.circle")
            }
            // Tapping the number opens a wheel: the ± are for shaving a second off a
            // mistimed hold, not for walking to 120 from zero.
            Button {
                showingTimeWheel = true
            } label: {
                Text("\(recordedSeconds)s")
                    .font(valueFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: isProminent ? 56 : 40)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingTimeWheel) {
                GlassNumberWheel(title: "Max time", value: $recordedSeconds, range: 0...3600) { "\($0)s" }
            }
            Button {
                recordedSeconds += 1
            } label: {
                Image(systemName: "plus.circle")
            }
        }
    }

    private var valueFont: Font {
        isProminent ? .title2.monospacedDigit().weight(.medium) : .subheadline.monospacedDigit()
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isLogged {
            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.appDanger)
        } else {
            switch phase {
            case .idle:
                Button("Start") { start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .stopped:
                Button("Log", action: onLog)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func start() {
        onStart()
        showingOverlay = true
    }
}
