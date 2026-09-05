import SwiftUI
import SwiftData

/// EMOM ("Every Minute On the Minute"): every exercise in the section is shown at
/// once — usually just a couple, meant to be done fast — behind a simple countdown
/// that repeats once per round. One round is always 60 seconds;
/// `section.emomRoundCount` rounds total.
///
/// A section set to `emomToFailure` instead runs open-ended: the rounds keep coming
/// until the user can't finish one inside the minute and taps the counter to stop. The
/// right half of the header becomes that control — the rounds *completed* over "tap to
/// finish" — mirroring AMRAP's tappable counter, so the two grid runners still read the
/// same way round.
struct EmomSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let cues: TimerCueSettings
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var remainingSeconds: Int = 60

    /// Counts down before the first round, when the section asks for one. `0` means the
    /// phase is over — or never existed, which is every section with `getReadySeconds == 0`.
    ///
    /// Local `@State` rather than a session field: `SessionRunnerView` keys this runner on
    /// the section *and its repeat*, so a repeated section re-seeds this and plays Get
    /// Ready before each pass — which is what a Follow Along section's real Get Ready step
    /// already does.
    @State private var getReadyRemaining: Int = 0

    private var isGettingReady: Bool { getReadyRemaining > 0 }

    /// Counting down the breather before the next pass. The rounds are all finished; only
    /// the clock is still running.
    @State private var sectionRestRemaining: Int = 0

    private var isSectionResting: Bool { sectionRestRemaining > 0 }

    private var currentRepeat: Int { session.currentSectionRepeat ?? 0 }

    /// Seeded from `WorkoutSessionService.autostartsRunning` — see `TimeSessionRunnerView`
    /// for why this is only gated once, at the section's first pass, not every round.
    @State private var isRunning: Bool


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

    /// Raised by tapping the round counter in a to-failure section. A confirmation, not
    /// an immediate stop: the counter occupies half a large header band, so a stray tap
    /// would otherwise end the section outright.
    @State private var showingFinishConfirm = false

    init(session: WorkoutSession, section: WorkoutSection, cues: TimerCueSettings, onSectionComplete: @escaping () -> Void) {
        self.session = session
        self.section = section
        self.cues = cues
        self.onSectionComplete = onSectionComplete
        _isRunning = State(initialValue: WorkoutSessionService.autostartsRunning(session, section: section))
    }

    /// 0-based, so it reads directly as *rounds completed*: during round 8 it is 7, which
    /// is exactly the number a to-failure section records when round 8 is the one missed.
    private var currentRound: Int { session.currentStepIndex ?? 0 }
    private var totalRounds: Int { section.emomRoundCount }

    /// A to-failure section has no round count to reach, so it never completes on its
    /// own — only the counter tap ends it.
    private var hasRunOutOfRounds: Bool { !section.emomToFailure && currentRound >= totalRounds }
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
        if !hasRunOutOfRounds {
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
            .onAppear {
                remainingSeconds = 60
                // Only on the way in. The per-round reset below must not restart it.
                if currentRound == 0 { getReadyRemaining = section.countInSeconds(pass: currentRepeat) }
                loadRecordToBeat()
            }
            .onChange(of: currentRound) { _, _ in remainingSeconds = 60 }
            // Stops outright while the round or the workout is paused, rather than
            // ticking and discarding it inside the handler.
            .secondTicker(isActive: isRunning && session.status == .inProgress) { tick() }
            .confirmationDialog(
                "End EMOM at \(currentRound) round\(currentRound == 1 ? "" : "s")?",
                isPresented: $showingFinishConfirm,
                titleVisibility: .visible
            ) {
                Button("End Section") { finishToFailure() }
                Button("Keep Going", role: .cancel) {}
            }
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

            // Timer leads, round count follows — the same order AMRAP uses, so the two
            // runners read the same way round.
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
                // Local pause only — the session clock keeps running and the grid
                // below stays fully visible and interactive. Stays bound to the
                // countdown, which is the half that pauses.
                .contentShape(Rectangle())
                .onTapGesture { isRunning.toggle() }

                // A plain Divider is invisible against the solid fill.
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                if canFinishToFailure {
                    // Deliberately the same shape as AMRAP's counter half: a big tally
                    // over a caption naming the tap. The number is rounds *completed*,
                    // which is what gets recorded — not the round in progress.
                    VStack(spacing: 4) {
                        Text("\(currentRound)")
                            .font(.system(size: glyphSize, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                        Text("rounds — tap to finish")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let recordToBeat {
                            recordCaption(recordToBeat)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { showingFinishConfirm = true }
                } else {
                    Text(headerCaption)
                        .font(.system(size: glyphSize * 0.5, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
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

    /// What the right half of the header says: the phase, when one is running, and the
    /// round tally the rest of the time.
    private var headerCaption: String {
        if isSectionResting { return "Rest" }
        if isGettingReady { return "Get Ready" }
        // Reached only by a fixed-round section: a to-failure one shows the tappable
        // counter in this half instead, and has no total to count towards.
        return "Round \(currentRound + 1) of \(totalRounds)"
    }

    /// Whether the header's right half is the stop control. The phases own that half
    /// while they run — there is nothing to bank mid count-in, and a section resting has
    /// already finished its rounds.
    private var canFinishToFailure: Bool {
        section.emomToFailure && !isSectionResting && !isGettingReady
    }

    /// Ends an open-ended section at the rounds completed so far. The result is filed
    /// *before* handing back control: `advanceSection` resets `currentStepIndex`, so the
    /// count is gone by the time the next section is on screen.
    private func finishToFailure() {
        SectionResultService.record(
            session: session,
            section: section,
            value: currentRound,
            repeatIndex: currentRepeat,
            context: context
        )
        onSectionComplete()
    }

    private func tick() {
        // The get-ready phase owns the clock until it's spent; the round timer is still
        // sitting at a full 60 and only starts counting once this returns to 0.
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
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, cues: cues)
        } else {
            SoundPlayer.playTimerCompleteIfNeeded(cues: cues)
            advance()
        }
    }

    private func advance() {
        let next = currentRound + 1
        // Open-ended: there is no last round to fall off the end of, so the counter just
        // keeps climbing until the user stops it.
        if section.emomToFailure {
            session.currentStepIndex = next
            session.markDirty()
            try? context.save()
            return
        }
        if next < totalRounds {
            session.currentStepIndex = next
            session.markDirty()
            try? context.save()
        } else {
            session.markDirty()
            try? context.save()
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
