import SwiftUI
import SwiftData
import Combine

/// EMOM ("Every Minute On the Minute"): every exercise in the section is shown at
/// once — usually just a couple, meant to be done fast — behind a simple countdown
/// that repeats once per round. One round is always 60 seconds;
/// `section.emomRoundCount` rounds total.
struct EmomSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let soundProfile: TimerSoundProfile
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context

    @State private var remainingSeconds: Int = 60

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentRound: Int { session.currentStepIndex ?? 0 }
    private var totalRounds: Int { section.emomRoundCount }
    private var exercises: [SectionExerciseEntry] { section.sortedQuickExercises }

    var body: some View {
        if currentRound < totalRounds {
            VStack(spacing: 24) {
                Text("Round \(currentRound + 1) of \(totalRounds)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(timeString(remainingSeconds))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())

                exerciseList

                Spacer()
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .onAppear { remainingSeconds = 60 }
            .onChange(of: currentRound) { _, _ in remainingSeconds = 60 }
            .onReceive(ticker) { _ in tick() }
        } else {
            Color.clear.onAppear { onSectionComplete() }
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(exercises) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text(entry.exercise?.displayName ?? "Exercise")
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tick() {
        guard session.status == .inProgress else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, profile: soundProfile)
        } else {
            SoundPlayer.playTimerComplete()
            advance()
        }
    }

    private func advance() {
        let next = currentRound + 1
        if next < totalRounds {
            session.currentStepIndex = next
            session.markDirty()
            try? context.save()
        } else {
            session.markDirty()
            try? context.save()
            onSectionComplete()
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
