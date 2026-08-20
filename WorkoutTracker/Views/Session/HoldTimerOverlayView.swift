import SwiftUI
import Combine

/// Full-screen replacement for the old small inline "Stop" button in `HoldSetRowView`
/// — same dimmed-scrim visual language as `SessionRunnerView`'s pause overlay, sized
/// for a big, easy-to-hit target since you're mid-hold (plank, wall sit, etc.), not
/// looking closely at the screen. Runs the head-start countdown then the count-up
/// stopwatch itself; tapping anywhere stops it and reports the elapsed seconds back.
struct HoldTimerOverlayView: View {
    let exerciseName: String
    let headStartSeconds: Int
    let previousBest: Int?
    let onStop: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case headStart, counting
    }

    @State private var phase: Phase
    @State private var headStartRemaining: Int
    @State private var elapsedSeconds = 0

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(exerciseName: String, headStartSeconds: Int, previousBest: Int?, onStop: @escaping (Int) -> Void) {
        self.exerciseName = exerciseName
        self.headStartSeconds = headStartSeconds
        self.previousBest = previousBest
        self.onStop = onStop
        _phase = State(initialValue: headStartSeconds > 0 ? .headStart : .counting)
        _headStartRemaining = State(initialValue: headStartSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(exerciseName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                switch phase {
                case .headStart:
                    Text("Get Ready")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(headStartRemaining)")
                        .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                case .counting:
                    Text(timeString(elapsedSeconds))
                        .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("Tap anywhere to stop")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture { stop() }
        .onReceive(ticker) { _ in tick() }
    }

    private func stop() {
        onStop(elapsedSeconds)
        dismiss()
    }

    private func tick() {
        switch phase {
        case .headStart:
            guard headStartRemaining > 0 else { return }
            headStartRemaining -= 1
            if headStartRemaining == 0 {
                elapsedSeconds = 0
                phase = .counting
                SoundPlayer.playTimerComplete()
            } else {
                SoundPlayer.playHeadStartTick()
            }
        case .counting:
            elapsedSeconds += 1
            if let previousBest, previousBest > 0, elapsedSeconds == previousBest {
                SoundPlayer.playTimerComplete()
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
