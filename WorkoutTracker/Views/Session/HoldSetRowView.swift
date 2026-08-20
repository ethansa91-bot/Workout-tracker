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

            // Same columns as `SetRowView`'s recap — number hard left, value across the
            // middle, button hard right — so both tracking modes read alike.
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            trailingControl
        }
        .opacity(isLogged ? 0.7 : 1)
    }

    private var prominentBody: some View {
        VStack(spacing: 20) {
            content
                .font(.title3)
            prominentControl
        }
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
            Text("\(recordedSeconds)s held")
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
            Text("\(recordedSeconds)s")
                .font(valueFont)
                .frame(minWidth: isProminent ? 72 : 40)
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
