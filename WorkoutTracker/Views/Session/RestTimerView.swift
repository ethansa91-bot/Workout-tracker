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

    var body: some View {
        // A plain, non-Button view here — a Button's own tap gesture recognizer
        // reliably swallows the touch before a co-attached `.onLongPressGesture`
        // ever sees it, so long-press-to-reset silently never fired when this was
        // wrapped in a Button.
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(timeString)
                    .font(.title3.monospacedDigit().bold())
                Text(isRunning ? "Tap to pause" : "Tap to start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !isRunning {
                    Text("Hold to reset")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
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

    private var progress: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return CGFloat(totalSeconds - remainingSeconds) / CGFloat(totalSeconds)
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
