import SwiftUI
import SwiftData

/// AMRAP ("As Many Rounds As Possible"): a single countdown for the whole section.
/// The header is one tappable strip — remaining time on the left, rounds completed on
/// the right, split by a divider — tapping anywhere in it counts one more round. The
/// rest of the screen lists the section's exercises in a responsive grid, all shown at
/// once since they're meant to be cycled through quickly, round after round.
struct AmrapSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let cues: TimerCueSettings
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

    /// Counts down after the section starts and before the AMRAP clock does, when the
    /// section asks for one. `0` means the phase is over — or never existed. Local
    /// `@State`, so a repeated section plays it again on each pass; see the EMOM runner.
    @State private var getReadyRemaining: Int = 0

    private var isGettingReady: Bool { getReadyRemaining > 0 }

    /// Counting down the breather before the next pass. The AMRAP clock is spent; only
    /// this one is still running.
    @State private var sectionRestRemaining: Int = 0

    private var isSectionResting: Bool { sectionRestRemaining > 0 }

    private var currentRepeat: Int { session.currentSectionRepeat ?? 0 }

    /// The standing record, read once on arrival rather than per render: it can't change
    /// while the section is running, and this view redraws every second.
    @State private var recordToBeat: Int?

    /// The record line under the counter. Absent until there is something to chase —
    /// a section that has never been done has no target, and "no record yet" under a
    /// live counter is noise.
    @ViewBuilder
    private func recordCaption(_ value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
            Text(PersonalRecordFormatting.sectionSummary(value))
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func loadRecordToBeat() {
        guard section.tracksRecord, let groupID = section.recordGroupID else { return }
        recordToBeat = PersonalRecordQueries.sectionRecord(groupID: groupID, context: context)?.reps
    }

    init(session: WorkoutSession, section: WorkoutSection, cues: TimerCueSettings, onSectionComplete: @escaping () -> Void) {
        self.session = session
        self.section = section
        self.cues = cues
        self.onSectionComplete = onSectionComplete
        let runsFromStart = WorkoutSessionService.autostartsRunning(session, section: section)
        _isRunning = State(initialValue: runsFromStart)
        _hasStarted = State(initialValue: runsFromStart)
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
    private var timerHeightFraction: CGFloat { horizontalSizeClass == .regular ? 0.45 : 0.24 }

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
        .onAppear {
            remainingSeconds = section.amrapDurationSeconds
            getReadyRemaining = section.countInSeconds(pass: currentRepeat)
            loadRecordToBeat()
        }
        // Stops outright while the section or the workout is paused, and once the
        // countdown is spent, rather than ticking and discarding it inside the handler.
        .secondTicker(isActive: isRunning && session.status == .inProgress && (remainingSeconds > 0 || isSectionResting)) { tick() }
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
                                Text(timeString(isSectionResting ? sectionRestRemaining : (isGettingReady ? getReadyRemaining : remainingSeconds)))
                                    .font(.system(size: glyphSize, weight: .bold, design: .rounded).monospacedDigit())
                                    .minimumScaleFactor(0.3)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: glyphSize))
                            }
                            Text(isRunning ? "Tap to pause" : "Paused — tap to resume")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        // Local pause only — the grid stays visible and interactive.
                        .contentShape(Rectangle())
                        .onTapGesture { isRunning.toggle() }

                        // A plain Divider is invisible against the solid fill.
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)

                        VStack(spacing: 4) {
                            if isSectionResting || isGettingReady {
                                Text(isSectionResting ? "Rest" : "Get Ready")
                                    .font(.system(size: glyphSize * 0.5, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            } else {
                                Text("\(completedRounds)")
                                    .font(.system(size: glyphSize, weight: .bold, design: .rounded).monospacedDigit())
                                    .minimumScaleFactor(0.3)
                                    .lineLimit(1)
                                Text("rounds — tap to count")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if let recordToBeat {
                                    recordCaption(recordToBeat)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { logRound() }
                        // Overlaid rather than placed in the stack: the whole half is
                        // the increment target, so an undo has to sit on top of it with
                        // its own hit area. The counter now feeds a personal record, and
                        // the tally was previously one-way — a stray tap on a target this
                        // big was unrecoverable.
                        //
                        // On the trailing edge, vertically centered rather than tucked in
                        // the top corner: `.trailing` lands it level with the round
                        // number, the biggest thing in this half, so it reads as *that
                        // number's* undo rather than a stray control up in the corner.
                        // Sized well past the glyph itself — the small top-corner icon
                        // this replaced was routinely missed, landing on the increment
                        // zone underneath instead of undoing anything.
                        .overlay(alignment: .trailing) {
                            if canUndoRound {
                                Button {
                                    undoRound()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 34))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .frame(width: 56, height: 56)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 14)
                                .accessibilityLabel("Undo last round")
                            }
                        }
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
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { start() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // White throughout — the solid accent fill matches Follow Along's timer
            // band, where dark text would be unreadable.
            .foregroundStyle(.white)
        }
        .background(Color.appAccent)
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
            VStack(spacing: 0) {
                // Outside the ScrollView so it stays put while the grid scrolls under
                // it, matching Follow Along. The tint also supplies the "Section: "
                // prefix, so all three runners read identically.
                SectionHeaderLabel(
                    section: section,
                    repeatIndex: session.currentSectionRepeat ?? 0,
                    tint: Color.appAccent
                )
                .padding(.horizontal, Self.gridPadding)
                .padding(.top, 8)

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
    }

    private func exerciseCell(_ entry: SectionExerciseEntry, mediaHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.cellSpacing) {
            Text(entry.displayTitle)
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
        // Nothing to bank while counting in — the AMRAP clock hasn't started yet.
        guard canCountRound else { return }
        session.currentSetIndex = completedRounds + 1
        session.markDirty()
        try? context.save()
    }

    /// Takes one back off the tally. Same conditions as counting one on, plus something
    /// to remove.
    private func undoRound() {
        guard canUndoRound else { return }
        session.currentSetIndex = max(0, completedRounds - 1)
        session.markDirty()
        try? context.save()
    }

    private var canCountRound: Bool {
        isRunning && !isGettingReady && !isSectionResting && session.status == .inProgress && remainingSeconds > 0
    }

    private var canUndoRound: Bool { canCountRound && completedRounds > 0 }

    private func tick() {
        // The get-ready phase owns the clock until it's spent; the AMRAP countdown is
        // still at its full duration and only starts once this returns to 0.
        if getReadyRemaining > 0 {
            getReadyRemaining -= 1
            SoundPlayer.playWarningIfNeeded(remainingSeconds: getReadyRemaining, cues: cues)
            if getReadyRemaining == 0 {
                SoundPlayer.playTimerCompleteIfNeeded(cues: cues)
            }
            return
        }
        // Then the between-passes rest, which likewise owns the clock until it's spent.
        if sectionRestRemaining > 0 {
            sectionRestRemaining -= 1
            SoundPlayer.playWarningIfNeeded(remainingSeconds: sectionRestRemaining, cues: cues)
            if sectionRestRemaining == 0 {
                SoundPlayer.playTimerCompleteIfNeeded(cues: cues)
                onSectionComplete()
            }
            return
        }
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, cues: cues)
        if remainingSeconds == 0 {
            SoundPlayer.playTimerCompleteIfNeeded(cues: cues)
            session.markDirty()
            try? context.save()
            // Filed here, ahead of both exits below, because `advanceSection` resets
            // `currentSetIndex` — the tally is gone the moment the section ends, whether
            // it ends straight away or after the rest.
            SectionResultService.record(
                session: session,
                section: section,
                value: completedRounds,
                repeatIndex: currentRepeat,
                context: context
            )
            // At the tail of this pass, not the head of the next: the runner is rebuilt
            // per pass, so there is no next instance to run it in yet.
            let rest = section.sectionRest(after: currentRepeat)
            guard rest > 0 else {
                onSectionComplete()
                return
            }
            sectionRestRemaining = rest
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
