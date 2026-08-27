import SwiftUI
import SwiftData
import Combine

struct TimeSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let soundProfile: TimerSoundProfile
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var remainingSeconds: Int = 0
    @State private var pendingJumpIndex: Int?
    @State private var showingJumpConfirm = false

    /// Seeded from `section.autostart` — once true (whether from autostart or a
    /// tapped play button), stays true for the rest of the section; only entering
    /// the section for the first time is gated, not every step within it.
    @State private var isRunning: Bool

    // Must be @State, not `let` — a plain `let` gets recomputed (a brand new Timer)
    // every time this View struct is reinitialized, which happens on every re-render
    // (i.e. every tick), so the timer rarely survives long enough to actually fire.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: WorkoutSession, section: WorkoutSection, soundProfile: TimerSoundProfile, onSectionComplete: @escaping () -> Void) {
        self.session = session
        self.section = section
        self.soundProfile = soundProfile
        self.onSectionComplete = onSectionComplete
        _isRunning = State(initialValue: section.autostart)
    }

    private var steps: [TimeSectionStep] { section.sortedTimeSteps }
    private var currentIndex: Int { session.currentStepIndex ?? 0 }
    private var currentStep: TimeSectionStep? {
        guard currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    private var timerHeightFraction: CGFloat { horizontalSizeClass == .regular ? 0.45 : 0.3 }

    /// The step's color, filling the timer area the same solid way the scrub strip
    /// fills its active chip. Always present now that "never chosen" resolves to a
    /// real selection — green for an exercise, gray for Rest/Get Ready.
    private var timerTint: Color { currentStep?.resolvedColor.color ?? Color.appAccent }

    /// Gray is a mid-tone, where white text washes out — everything else in the
    /// palette is deep enough to carry it.
    private var timerForeground: Color {
        currentStep?.resolvedColor == .gray ? Color.appInk : .white
    }

    var body: some View {
        if let currentStep {
            GeometryReader { geometry in
                if isWideLayout(geometry) {
                    wideBody(currentStep)
                } else {
                    compactBody(currentStep, geometry: geometry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .onAppear {
                remainingSeconds = currentStep.durationSeconds
                announceCurrentStep()
            }
            .onChange(of: currentIndex) { _, _ in
                remainingSeconds = self.currentStep?.durationSeconds ?? 0
                announceCurrentStep()
            }
            .onDisappear { SpeechAnnouncer.stop() }
            .onReceive(ticker) { _ in tick() }
            .confirmationDialog(
                jumpConfirmMessage,
                isPresented: $showingJumpConfirm,
                titleVisibility: .visible
            ) {
                Button(jumpConfirmActionTitle, role: .destructive) { confirmJump() }
            }
        } else {
            Color.clear.onAppear { onSectionComplete() }
        }
    }

    /// iPad in landscape (regular width, wider than tall) keeps the pre-timer-first
    /// layout: timer on the left, title/media on the right, side by side — just with
    /// a bigger timer than before.
    private func isWideLayout(_ geometry: GeometryProxy) -> Bool {
        horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
    }

    private func compactBody(_ step: TimeSectionStep, geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            timerArea
                .frame(height: geometry.size.height * timerHeightFraction)
                .frame(maxWidth: .infinity)
            Divider()
            // 0, not 12: the only gap that matters here is above the section title,
            // which supplies its own padding. A stack spacing would also push the
            // scrub strip away from the bar below it.
            VStack(spacing: 0) {
                // Outside the ScrollView, so it stays put while the exercise content
                // scrolls under it.
                sectionTitleLabel
                    .padding(.horizontal)
                    .padding(.top, 12)
                Group {
                    if step.stepType == .exercise {
                        // Exercise steps carry the media box, which can be tall enough
                        // to need scrolling — Rest/Get Ready are short and just center
                        // in the available space instead.
                        ScrollView {
                            titleMediaView(step)
                        }
                        .padding(.bottom, 8)
                    } else {
                        VStack {
                            Spacer(minLength: 0)
                            titleMediaView(step)
                            Spacer(minLength: 0)
                        }
                    }
                }
                SessionScrubStripView(
                    steps: steps,
                    currentIndex: currentIndex,
                    completedIndices: completedIndices,
                    onSelect: requestJump,
                    fixedHeight: SessionScrubStripView.height(for: geometry.size.width)
                )
                // `appSurface` is what the runner's bottom control bar uses, so the
                // strip and the bar read as one connected block rather than the strip
                // floating on the page background above it. Tight vertical padding
                // keeps it close to the progress bar, leaving more room above for the
                // exercise itself.
                .padding(.vertical, 4)
                .background(Color.appSurface)
            }
        }
    }

    private func wideBody(_ step: TimeSectionStep) -> some View {
        // Zero spacing: any gap here shows the page background between the timer's
        // colored fill and the scrub strip, leaving the color floating instead of
        // running all the way down to the strip.
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                timerArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack(spacing: 12) {
                    sectionTitleLabel
                        .padding(.horizontal)
                        .padding(.top, 12)
                    Group {
                        if step.stepType == .exercise {
                            ScrollView {
                                titleMediaView(step)
                                    .padding()
                            }
                        } else {
                            VStack {
                                Spacer(minLength: 0)
                                titleMediaView(step)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            SessionScrubStripView(
                steps: steps,
                currentIndex: currentIndex,
                completedIndices: completedIndices,
                onSelect: requestJump
            )
            // Same surface as the bottom control bar, matching the phone layout.
            .padding(.vertical, 8)
            .background(Color.appSurface)
        }
    }

    /// The counter number itself reserves 40% of the timer area's height and its font
    /// scales to fill that reserved band, centered in whatever space remains. The step's
    /// own icon and title live together in `titleMediaView` below, not here.
    private var timerArea: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                if isRunning {
                    Text(timeString(remainingSeconds))
                        .font(.system(size: geometry.size.height * 0.4, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .frame(height: geometry.size.height * 0.4)
                        .foregroundStyle(timerForeground)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: geometry.size.height * 0.4))
                        .foregroundStyle(timerForeground)
                        .frame(height: geometry.size.height * 0.4)
                }
                Text(isRunning ? "Tap to pause" : "Paused — tap to resume")
                    .font(.caption2)
                    // `.secondary` all but disappears on a saturated fill.
                    .foregroundStyle(timerForeground.opacity(0.85))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background(timerTint)
            // A plain tap target rather than a Button — see RestTimerView, where a
            // Button's own recognizer swallowed co-attached gestures. Pausing here is
            // local to the section: the session clock keeps running and the screen
            // stays awake, so the video and description stay readable while stopped.
            .contentShape(Rectangle())
            .onTapGesture { isRunning.toggle() }
        }
    }

    /// Rest and Get Ready have no media, just a symbol and a word — kept on one line so
    /// the icon reads as part of the label rather than floating off in the timer pane.
    /// Sizing the symbol from the shared `.title` font keeps the two scaling together.
    /// Symbol stacked above the word, both at roughly the countdown's scale so Rest and
    /// Get Ready carry the same weight as the timer rather than reading as a caption.
    private func statusLabel(_ systemImage: String, _ title: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 72))
            Text(title)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .foregroundStyle(Color.appInk)
        .padding(.vertical, 24)
    }

    /// No `GeometryReader` around this one: the exercise branch lives inside a
    /// `ScrollView`, where a reader reports the collapsed content height and would
    /// shrink the media box. Only the branches that scale with available space —
    /// Rest/Get Ready and a media-less name — take a reader, and they render outside
    /// the scroll view.
    private func titleMediaView(_ step: TimeSectionStep) -> some View {
        VStack(spacing: 12) {
            switch step.stepType {
            case .exercise:
                if let exercise = step.exercise {
                    if ExerciseMediaView.hasMedia(exercise) {
                        // Unchanged from before: fixed box, `.title` name beneath it.
                        ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: min(30, Double(step.durationSeconds))), fillsWidth: true)
                            .id(exercise.id)
                            .padding(.horizontal)
                        Text(exercise.displayName)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                    } else {
                        // Nothing to show, so the placeholder box is dropped entirely
                        // and the name takes the freed space.
                        Text(exercise.displayName)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.4)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 24)
                    }
                    ExerciseDescriptionView(exercise: exercise)
                        .id(exercise.id)
                    // Read-only here — notes are entered from the end-of-workout
                    // summary, but what you noted last time is worth seeing mid-set.
                    ExerciseNotePreview(session: session, exercise: exercise)
                        .id(exercise.id)
                } else {
                    Text("Exercise")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                }
            case .rest:
                statusLabel("pause.circle.fill", "Rest")
            case .getReady:
                statusLabel("hourglass", "Get Ready")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        // A media box sits right under the pinned section title, so it only needs a
        // little breathing room; the no-media branch keeps the roomier padding it
        // relies on to center its large name.
        .padding(.top, hasMediaStep(step) ? 4 : 24)
        .padding(.bottom, 24)
    }

    /// Whether this step will render a media box — drives how much space to leave
    /// between the pinned section title and the content below it.
    private func hasMediaStep(_ step: TimeSectionStep) -> Bool {
        guard step.stepType == .exercise, let exercise = step.exercise else { return false }
        return ExerciseMediaView.hasMedia(exercise)
    }

    /// The section name, tinted with the current step's color so it reads as part of
    /// the same block — falling back to the app green when the step has no color of
    /// its own.
    private var sectionTitleLabel: some View {
        SectionHeaderLabel(
            section: section,
            repeatIndex: currentRepeat,
            tint: timerTint
        )
    }

    /// Scoped to the current pass — on a repeated section the earlier passes' logs are
    /// still present, and without this filter the strip would show every step already
    /// completed from the first frame of round 2.
    private var completedIndices: Set<Int> {
        Set(session.stepLogs.compactMap { log -> Int? in
            guard log.repeatIndex == currentRepeat, let step = log.timeSectionStep else { return nil }
            return steps.firstIndex(where: { $0.id == step.id })
        })
    }

    private var currentRepeat: Int { session.currentSectionRepeat ?? 0 }

    private var jumpConfirmMessage: String {
        guard let pendingJumpIndex else { return "" }
        if pendingJumpIndex > currentIndex {
            return "Skip ahead to this step? Everything in between will be marked skipped."
        } else {
            return "Redo this step? Progress on it and everything after will be cleared."
        }
    }

    private var jumpConfirmActionTitle: String {
        guard let pendingJumpIndex else { return "Jump" }
        return pendingJumpIndex > currentIndex ? "Skip Ahead" : "Redo"
    }

    // MARK: - Spoken cues

    /// What a step is called out loud. `displayName` rather than `name` — a person is
    /// listening, so the friendly label is the right one (the opposite of the export,
    /// where a parser reads the string and needs the catalog name).
    private func spokenName(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    /// One combined cue at ten seconds: how long is left, and what's coming next.
    /// Skipped on steps barely longer than the cue itself, where it would land almost
    /// on top of the step-start announcement.
    private func announceWarningIfNeeded() {
        guard AppSettings.speechEnabled, remainingSeconds == 10 else { return }
        guard let currentStep, currentStep.durationSeconds >= 12 else { return }

        let nextIndex = currentIndex + 1
        guard nextIndex < steps.count else {
            SpeechAnnouncer.speak("Ten seconds left")
            return
        }
        SpeechAnnouncer.speak("Ten seconds left. Next: \(spokenName(for: steps[nextIndex]))")
    }

    private func announceCurrentStep() {
        guard AppSettings.speechEnabled, let currentStep else { return }
        SpeechAnnouncer.speak(spokenName(for: currentStep))
    }

    private func tick() {
        guard isRunning, session.status == .inProgress else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, profile: soundProfile)
            announceWarningIfNeeded()
        } else {
            completeCurrentStep()
        }
    }

    private func completeCurrentStep() {
        guard let currentStep else { return }
        SoundPlayer.playTimerComplete()
        logStep(currentStep, outcome: .completed, actualDuration: currentStep.durationSeconds)
        advance()
    }

    private func logStep(_ step: TimeSectionStep, outcome: StepOutcome, actualDuration: Int) {
        // The guard is per pass: a repeated section legitimately logs the same step
        // again on each round, so the step reference alone can't be the identity.
        guard !session.stepLogs.contains(where: {
            $0.timeSectionStep?.id == step.id && $0.repeatIndex == currentRepeat
        }) else { return }
        let log = StepLog(
            session: session,
            timeSectionStep: step,
            stepExerciseNameSnapshot: step.exercise?.displayName,
            plannedDurationSeconds: step.durationSeconds,
            actualDurationSeconds: max(0, actualDuration),
            outcome: outcome,
            sortOrder: steps.firstIndex(where: { $0.id == step.id }) ?? 0,
            repeatIndex: currentRepeat
        )
        context.insert(log)
    }

    private func advance() {
        let next = currentIndex + 1
        if next < steps.count {
            session.currentStepIndex = next
            session.markDirty()
            try? context.save()
        } else {
            session.markDirty()
            try? context.save()
            onSectionComplete()
        }
    }

    private func requestJump(to index: Int) {
        guard index != currentIndex else { return }
        pendingJumpIndex = index
        showingJumpConfirm = true
    }

    private func confirmJump() {
        guard let pendingJumpIndex else { return }
        if pendingJumpIndex > currentIndex {
            for i in currentIndex..<pendingJumpIndex {
                logStep(steps[i], outcome: .skipped, actualDuration: 0)
            }
        } else {
            let idsToClear = Set(steps[pendingJumpIndex...].map(\.id))
            for log in session.stepLogs where log.timeSectionStep.map({ idsToClear.contains($0.id) }) ?? false {
                context.delete(log)
            }
        }
        session.currentStepIndex = pendingJumpIndex
        session.markDirty()
        try? context.save()
        self.pendingJumpIndex = nil
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
