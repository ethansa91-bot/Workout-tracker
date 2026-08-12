import SwiftUI
import Combine

/// Rest countdown — a normal tap starts/pauses/resumes it; it also auto-starts
/// (only if not already running) whenever the caller bumps `startSignal`, which
/// happens once per logged set; holding the button resets it back to full duration.
struct RestTimerView: View {
    let totalSeconds: Int
    let soundProfile: TimerSoundProfile
    @Binding var startSignal: Int

    @State private var remainingSeconds: Int
    @State private var isRunning = false

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(totalSeconds: Int, soundProfile: TimerSoundProfile, startSignal: Binding<Int>) {
        self.totalSeconds = totalSeconds
        self.soundProfile = soundProfile
        _startSignal = startSignal
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
                Text(isRunning ? "Resting" : "Tap to rest")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            guard isRunning else { return }
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
