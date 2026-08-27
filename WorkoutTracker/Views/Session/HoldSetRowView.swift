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
    /// An unloaded hold has no left column, so it keeps the plain centred stopwatch it has
    /// always had — the `×` has to go with the weight or it's left dangling.
    @ViewBuilder
    private var valueColumns: some View {
        if weightMode == .bodyweight {
            content
                .frame(maxWidth: .infinity, alignment: isProminent ? .center : .leading)
        } else if isLogged || phase == .stopped {
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

    /// Only for a loaded hold: an unloaded one has nothing to show, so the row keeps the
    /// plain stopwatch layout it has always had.
    @ViewBuilder
    private var weightRow: some View {
        if weightMode != .bodyweight {
            HStack(spacing: isProminent ? 12 : 4) {
                Image(systemName: "scalemass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLogged {
                    Text(weightLabel)
                        .font(valueFont)
                } else {
                    switch weightMode {
                    case .stepper:
                        Button {
                            step(-1)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        Text(weightLabel)
                            .font(valueFont)
                            .frame(minWidth: isProminent ? 92 : 60)
                        Button {
                            step(1)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    case .manual:
                        Button {
                            showingWheel = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(weightLabel)
                                    .font(valueFont)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, isProminent ? 6 : 2)
                            .padding(.horizontal, 8)
                            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appHairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    case .bodyweight:
                        EmptyView()
                    }
                }
            }
            .sheet(isPresented: $showingWheel) {
                weightWheelSheet
            }
        }
    }

    private var weightLabel: String {
        isBodyweight.wrappedValue ? "Bodyweight" : formattedSetWeight(weight.wrappedValue, unit: weightUnit)
    }

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
        HStack(spacing: isProminent ? 12 : 4) {
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
                    .frame(minWidth: isProminent ? 72 : 40)
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
