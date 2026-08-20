import SwiftUI
import Combine

/// Rest countdown — a normal tap starts/pauses/resumes it; it also auto-starts
/// (only if not already running) whenever the caller bumps `startSignal`, which
/// happens once per logged set; holding the button resets it back to full duration.
/// Bumping `stopSignal` force-stops and resets it regardless of running/paused
/// state — used when a max-hold-time stopwatch starts, since resting and holding
/// at the same time doesn't make sense.
struct RestTimerView: View {
    let totalSeconds: Int
    let soundProfile: TimerSoundProfile
    /// `session.status == .inProgress` — the timer freezes while the overall
    /// workout is paused, same as the step countdown in `TimeSessionRunnerView`.
    let isSessionActive: Bool
    @Binding var startSignal: Int
    @Binding var stopSignal: Int

    @State private var remainingSeconds: Int
    @State private var isRunning = false

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(totalSeconds: Int, soundProfile: TimerSoundProfile, isSessionActive: Bool, startSignal: Binding<Int>, stopSignal: Binding<Int>) {
        self.totalSeconds = totalSeconds
        self.soundProfile = soundProfile
        self.isSessionActive = isSessionActive
        _startSignal = startSignal
        _stopSignal = stopSignal
        _remainingSeconds = State(initialValue: totalSeconds)
    }

    private static let cornerRadius: CGFloat = 16
    private static let height: CGFloat = 132
    private static let ringWidth: CGFloat = 6

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// How much rest is left, 0...1 — what the ring draws. Guarded so a zero total
    /// can't divide by zero.
    private var progress: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, CGFloat(remainingSeconds) / CGFloat(totalSeconds)))
    }

    /// The dial itself: a depleting ring with the remaining time at its centre.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: Self.ringWidth)
            // A Circle trims cleanly along its own outline — a RoundedRectangle
            // doesn't, which is why an earlier version's arc spilled outside.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)

            Text(timeString)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, Self.ringWidth + 4)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var captions: some View {
        // Larger where there's room beside the ring; the compact layout keeps the small
        // type that fits under it.
        let isRegular = horizontalSizeClass == .regular
        return VStack(alignment: .center, spacing: 2) {
            Text(isRunning ? "Tap to pause" : "Tap to start")
                .font(isRegular ? .title3 : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !isRunning {
                Text("Hold to reset")
                    .font(isRegular ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
    }

    var body: some View {
        // A plain, non-Button view here — a Button's own tap gesture recognizer
        // reliably swallows the touch before a co-attached `.onLongPressGesture`
        // ever sees it, so long-press-to-reset silently never fired when this was
        // wrapped in a Button.
        Group {
            if horizontalSizeClass == .regular {
                // Wide enough to read side by side — the captions sit beside the ring
                // instead of stacking under it and squeezing its height.
                HStack(spacing: 12) {
                    ring
                        .padding(.leading, 5)
                    // Centered in whatever's left beside the ring, rather than pinned to
                    // its leading edge.
                    captions
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    ring
                    captions
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        // Same surface as the set block beside it, so the header reads as two panels of
        // one screen rather than two different materials.
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onTapGesture {
            toggle()
        }
        .onLongPressGesture(minimumDuration: 1) {
            guard !isRunning else { return }
            remainingSeconds = totalSeconds
        }
        .onReceive(ticker) { _ in
            guard isRunning && isSessionActive else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, profile: soundProfile)
            } else {
                isRunning = false
                SoundPlayer.playTimerComplete()
            }
        }
        .onChange(of: totalSeconds) { _, newValue in
            remainingSeconds = newValue
            isRunning = false
        }
        .onChange(of: startSignal) { _, _ in
            guard !isRunning else { return }
            remainingSeconds = totalSeconds
            isRunning = true
        }
        .onChange(of: stopSignal) { _, _ in
            remainingSeconds = totalSeconds
            isRunning = false
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func toggle() {
        if isRunning {
            isRunning = false
        } else {
            if remainingSeconds == 0 { remainingSeconds = totalSeconds }
            isRunning = true
        }
    }
}
