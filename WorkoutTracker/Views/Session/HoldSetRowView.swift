import SwiftUI
import Combine

/// One max-hold-time set: idle → head-start countdown → counting up → stopped
/// (correctable before confirming), or logged (read-only with a Cancel action) —
/// the stopwatch counterpart to `SetRowView`'s reps/weight row.
struct HoldSetRowView: View {
    let setNumber: Int
    let headStartSeconds: Int
    /// The best hold ever recorded for this exercise (nil if there's no history yet).
    /// When the live count-up reaches it, a "reached your best" cue plays once.
    let previousBest: Int?
    @Binding var recordedSeconds: Int
    let isLogged: Bool
    var onStart: () -> Void = {}
    let onLog: () -> Void
    let onCancel: () -> Void

    private enum Phase {
        case idle, headStart, counting, stopped
    }

    @State private var phase: Phase = .idle
    @State private var headStartRemaining = 0
    @State private var elapsedSeconds = 0

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(setNumber)")
                .font(.subheadline.weight(.medium))
                .frame(width: 46, alignment: .leading)

            content

            // Capped, not a full flex Spacer — keeps the button close to the row's
            // content instead of snapping to the far trailing edge on wide screens.
            Spacer(minLength: 12).frame(maxWidth: 24)

            trailingControl
        }
        .opacity(isLogged ? 0.7 : 1)
        .onReceive(ticker) { _ in tick() }
    }

    @ViewBuilder
    private var content: some View {
        if isLogged {
            Text("\(recordedSeconds)s held")
                .font(.subheadline.monospacedDigit())
        } else {
            switch phase {
            case .idle:
                Text("Not started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .headStart:
                Text("Get ready… \(headStartRemaining)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .counting:
                Text(timeString(elapsedSeconds))
                    .font(.subheadline.monospacedDigit().bold())
            case .stopped:
                stoppedStepper
            }
        }
    }

    private var stoppedStepper: some View {
        HStack(spacing: 4) {
            Button {
                if recordedSeconds > 0 { recordedSeconds -= 1 }
            } label: {
                Image(systemName: "minus.circle")
            }
            Text("\(recordedSeconds)s")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 40)
            Button {
                recordedSeconds += 1
            } label: {
                Image(systemName: "plus.circle")
            }
        }
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
            case .headStart, .counting:
                Button("Stop") { stop() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
            case .stopped:
                Button("Log", action: onLog)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func start() {
        onStart()
        headStartRemaining = headStartSeconds
        if headStartRemaining > 0 {
            phase = .headStart
        } else {
            elapsedSeconds = 0
            phase = .counting
            SoundPlayer.playTimerComplete()
        }
    }

    private func stop() {
        recordedSeconds = elapsedSeconds
        phase = .stopped
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
        case .idle, .stopped:
            break
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
