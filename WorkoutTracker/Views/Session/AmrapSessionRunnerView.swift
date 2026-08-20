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

    /// Seeded from `section.autostart` — see `TimeSessionRunnerView` for why this is
    /// only gated once, at section entry.
    @State private var isRunning: Bool

    /// Separate from `isRunning` so the header can tell "not started yet" (show
    /// "Tap to start" across the whole strip) from "started but paused" (show the
    /// two-column layout with a resume affordance on the timer half).
    @State private var hasStarted: Bool

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: WorkoutSession, section: WorkoutSection, soundProfile: TimerSoundProfile, onSectionComplete: @escaping () -> Void) {
        self.session = session
        self.section = section
        self.soundProfile = soundProfile
        self.onSectionComplete = onSectionComplete
        _isRunning = State(initialValue: section.autostart)
        _hasStarted = State(initialValue: section.autostart)
    }

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

    /// Same share of the container the Follow Along runner gives its timer, so the
    /// countdown reads at a comparable size across section types.
    private var timerHeightFraction: CGFloat { horizontalSizeClass == .regular ? 0.45 : 0.3 }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                counterArea
                    .frame(height: geometry.size.height * timerHeightFraction)
                    .frame(maxWidth: .infinity)

                Divider()

                exerciseList
            }
        }
        .background(Color.appBackground)
        .onAppear { remainingSeconds = section.amrapDurationSeconds }
        .onReceive(ticker) { _ in tick() }
    }

    /// Time remaining and rounds completed side by side, not stacked, so the header
    /// takes proportionally the same share of the screen the Follow Along timer does.
    ///
    /// The two halves are separate tap targets: the countdown pauses and resumes the
    /// section, the rounds counter logs a round. They used to share one strip-wide
    /// gesture, which left nowhere to put a pause.
    private var counterArea: some View {
        GeometryReader { geometry in
            let glyphSize = geometry.size.height * 0.4

            Group {
                if hasStarted {
                    HStack(spacing: 0) {
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
                        // Local pause only — the grid stays visible and interactive.
                        .contentShape(Rectangle())
                        .onTapGesture { isRunning.toggle() }

                        Divider()

                        VStack(spacing: 4) {
                            Text("\(completedRounds)")
                                .font(.system(size: glyphSize, weight: .bold, design: .rounded).monospacedDigit())
                                .minimumScaleFactor(0.3)
                                .lineLimit(1)
                            Text("rounds — tap to count")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { logRound() }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: glyphSize))
                        Text("Tap to start")
                            .font(.system(size: glyphSize * 0.4, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Color.appAccent)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { start() }
                }
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

    private func start() {
        isRunning = true
        hasStarted = true
    }

    private func logRound() {
        guard isRunning, session.status == .inProgress, remainingSeconds > 0 else { return }
        session.currentSetIndex = completedRounds + 1
        session.markDirty()
        try? context.save()
    }

    private func tick() {
        guard isRunning, session.status == .inProgress, remainingSeconds > 0 else { return }
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
