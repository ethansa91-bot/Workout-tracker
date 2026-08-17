import SwiftUI
import SwiftData
import Combine

/// AMRAP ("As Many Rounds As Possible"): a single countdown for the whole section.
/// The header is one tappable strip — remaining time on the left, rounds completed on
/// the right, split by a divider — tapping anywhere in it counts one more round. The
/// rest of the screen lists the section's exercises in a responsive grid, all shown at
/// once since they're meant to be cycled through quickly, round after round.
struct AmrapSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let soundProfile: TimerSoundProfile
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var remainingSeconds: Int = 0

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var completedRounds: Int { session.currentSetIndex ?? 0 }
    private var exercises: [SectionExerciseEntry] { section.sortedQuickExercises }

    /// 3 columns on iPad, 2 on iPhone — as many exercises visible at once without
    /// scrolling as a single column would allow.
    private var columnCount: Int { horizontalSizeClass == .regular ? 3 : 2 }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.columnSpacing), count: columnCount)
    }

    private static let gridPadding: CGFloat = 16
    private static let columnSpacing: CGFloat = 16
    private static let rowSpacing: CGFloat = 16
    private static let cellSpacing: CGFloat = 6
    private static let titleHeight: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                counterArea
                    .frame(height: geometry.size.height * 0.2)
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

    /// Time remaining and rounds completed side by side, not stacked, so the header
    /// takes noticeably less height (pinned to 20% of the available height above) — the
    /// whole strip (both halves) stays one tap target for logging a round.
    private var counterArea: some View {
        HStack(spacing: 0) {
            Text(timeString(remainingSeconds))
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
            Divider()
            VStack(spacing: 4) {
                Text("\(completedRounds)")
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                Text("rounds — tap to count")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.appAccent.opacity(0.12))
    }

    /// Width drives height here, not the other way around — 2 columns on iPhone, 3 on
    /// iPad, and each cell's media keeps the same 16:9 ratio used everywhere else in
    /// the app (`ExerciseMediaView`'s own `maxWidth = height * 16/9`), derived from
    /// the actual column width so it's never stretched or squished to fit a row.
    private var exerciseList: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - Self.gridPadding * 2 - Self.columnSpacing * CGFloat(columnCount - 1)
            let cellWidth = availableWidth / CGFloat(columnCount)
            let mediaHeight = cellWidth * 9 / 16
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(exercises) { entry in
                        exerciseCell(entry, mediaHeight: mediaHeight)
                    }
                }
                .padding(Self.gridPadding)
            }
        }
    }

    private func exerciseCell(_ entry: SectionExerciseEntry, mediaHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.cellSpacing) {
            Text(entry.exercise?.displayName ?? "Exercise")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: Self.titleHeight, alignment: .leading)
            if let exercise = entry.exercise {
                ExerciseMediaView(exercise: exercise, mode: .photoOnly, height: mediaHeight)
                    .id(exercise.id)
            }
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
