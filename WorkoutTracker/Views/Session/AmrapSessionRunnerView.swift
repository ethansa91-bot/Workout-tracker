import SwiftUI
import SwiftData
import Combine

/// AMRAP ("As Many Rounds As Possible"): a single countdown for the whole section.
/// The top third of the screen is a big tap target that shows the countdown and the
/// rounds-completed count together — tapping anywhere in it just counts one more
/// round. The rest of the screen lists the section's exercises, all shown at once
/// since they're meant to be cycled through quickly, round after round.
struct AmrapSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let soundProfile: TimerSoundProfile
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context

    @State private var remainingSeconds: Int = 0

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var completedRounds: Int { session.currentSetIndex ?? 0 }
    private var exercises: [SectionExerciseEntry] { section.sortedQuickExercises }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                counterArea
                    .frame(height: geometry.size.height / 3)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { logRound() }

                Divider()

                exerciseList
            }
        }
        .background(Color.appBackground)
        .onAppear { remainingSeconds = section.amrapDurationSeconds }
        .onReceive(ticker) { _ in tick() }
    }

    private var counterArea: some View {
        VStack(spacing: 6) {
            Text(timeString(remainingSeconds))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(completedRounds)")
                .font(.system(size: 72, weight: .heavy, design: .rounded))
            Text("rounds — tap to count")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appAccent.opacity(0.12))
    }

    private var exerciseList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(exercises) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        Text(entry.exercise?.name ?? "Exercise")
                            .font(.title3.weight(.semibold))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func logRound() {
        guard session.status == .inProgress, remainingSeconds > 0 else { return }
        session.currentSetIndex = completedRounds + 1
        session.markDirty()
        try? context.save()
    }

    private func tick() {
        guard session.status == .inProgress, remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, profile: soundProfile)
        if remainingSeconds == 0 {
            SoundPlayer.playTimerComplete()
            session.markDirty()
            try? context.save()
            onSectionComplete()
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
