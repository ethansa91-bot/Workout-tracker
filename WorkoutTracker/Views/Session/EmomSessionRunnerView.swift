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

    /// Seeded from `section.autostart` — see `TimeSessionRunnerView` for why this is
    /// only gated once, at section entry, not every round.
    @State private var isRunning: Bool

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: WorkoutSession, section: WorkoutSection, soundProfile: TimerSoundProfile, onSectionComplete: @escaping () -> Void) {
        self.session = session
        self.section = section
        self.soundProfile = soundProfile
        self.onSectionComplete = onSectionComplete
        _isRunning = State(initialValue: section.autostart)
    }

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

    /// Same share of the container the Follow Along runner gives its timer, so the
    /// countdown reads at a comparable size across section types.
    private var timerHeightFraction: CGFloat { horizontalSizeClass == .regular ? 0.45 : 0.3 }

    var body: some View {
        if currentRound < totalRounds {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    header
                        .frame(height: geometry.size.height * timerHeightFraction)
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
    /// Before the section has started (Autostart off), a play button takes the
    /// timer's place; tapping it starts the section.
    private var header: some View {
        GeometryReader { geometry in
            // Font scales with the band the header was given, the way the Follow Along
            // timer does, instead of a fixed size floating in mostly empty space.
            let glyphSize = geometry.size.height * 0.4

            HStack(spacing: 0) {
                Text("Round \(currentRound + 1) of \(totalRounds)")
                    .font(.system(size: glyphSize * 0.5, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Divider()

                VStack(spacing: 4) {
                    if isRunning {
                        Text(timeString(remainingSeconds))
                            .font(.system(size: glyphSize, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: glyphSize))
                            .foregroundStyle(Color.appAccent)
                    }
                    Text(isRunning ? "Tap to pause" : "Paused — tap to resume")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                // Local pause only — the session clock keeps running and the grid
                // below stays fully visible and interactive.
                .contentShape(Rectangle())
                .onTapGesture { isRunning.toggle() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                SectionHeaderLabel(section: section, repeatIndex: session.currentSectionRepeat ?? 0)
                    .padding(.horizontal, Self.gridPadding)
                    .padding(.top, 8)
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
                ExerciseDescriptionView(exercise: exercise, style: .gridButton)
                    .id(exercise.id)
            }
        }
        // Grid rows are height-matched to their tallest cell; pinning to the top keeps
        // every cell's media on the same baseline if a row is ever stretched.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tick() {
        guard isRunning, session.status == .inProgress else { return }
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
