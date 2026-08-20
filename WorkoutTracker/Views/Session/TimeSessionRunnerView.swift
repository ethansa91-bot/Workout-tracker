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
            .onAppear { remainingSeconds = currentStep.durationSeconds }
            .onChange(of: currentIndex) { _, _ in remainingSeconds = self.currentStep?.durationSeconds ?? 0 }
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
            VStack(spacing: 12) {
                Group {
                    if step.stepType == .exercise {
                        // Exercise steps carry the media box, which can be tall enough
                        // to need scrolling — Rest/Get Ready are short and just center
                        // in the available space instead.
                        ScrollView {
                            titleMediaView(step)
                                .padding(.vertical)
                        }
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
                    onSelect: requestJump
                )
            }
        }
    }

    private func wideBody(_ step: TimeSectionStep) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                timerArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            SessionScrubStripView(
                steps: steps,
                currentIndex: currentIndex,
                completedIndices: completedIndices,
                onSelect: requestJump
            )
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
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: geometry.size.height * 0.4))
                        .foregroundStyle(Color.appAccent)
                        .frame(height: geometry.size.height * 0.4)
                }
                Text(isRunning ? "Tap to pause" : "Paused — tap to resume")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
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
    private func statusLabel(_ systemImage: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.title.bold())
        .foregroundStyle(.secondary)
    }

    private func titleMediaView(_ step: TimeSectionStep) -> some View {
        VStack(spacing: 12) {
            SectionHeaderLabel(section: section, repeatIndex: currentRepeat)

            switch step.stepType {
            case .exercise:
                if let exercise = step.exercise {
                    ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: min(30, Double(step.durationSeconds))), fillsWidth: true)
                        .id(exercise.id)
                        .padding(.horizontal)
                    Text(exercise.displayName)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
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
        .padding(.vertical, 24)
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

    private func tick() {
        guard isRunning, session.status == .inProgress else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            SoundPlayer.playWarningIfNeeded(remainingSeconds: remainingSeconds, profile: soundProfile)
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
