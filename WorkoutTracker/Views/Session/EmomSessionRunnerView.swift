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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var remainingSeconds: Int = 60

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentRound: Int { session.currentStepIndex ?? 0 }
    private var totalRounds: Int { section.emomRoundCount }
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
        if currentRound < totalRounds {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    header
                        .frame(height: geometry.size.height * 0.2)
                        .frame(maxWidth: .infinity)
                    Divider()
                    exerciseList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .onAppear { remainingSeconds = 60 }
            .onChange(of: currentRound) { _, _ in remainingSeconds = 60 }
            .onReceive(ticker) { _ in tick() }
        } else {
            Color.clear.onAppear { onSectionComplete() }
        }
    }

    /// Round and time remaining side by side, not stacked, so the header takes
    /// noticeably less height (pinned to 20% of the available height above) — same
    /// background tint as AMRAP's header for visual consistency between the two.
    private var header: some View {
        HStack(spacing: 0) {
            Text("Round \(currentRound + 1) of \(totalRounds)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            Divider()
            Text(timeString(remainingSeconds))
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
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
