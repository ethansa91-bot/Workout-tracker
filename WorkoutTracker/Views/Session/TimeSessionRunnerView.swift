import SwiftUI
import SwiftData

struct TimeSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let cues: TimerCueSettings
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var remainingSeconds: Int = 0
    @State private var pendingJumpIndex: Int?
    @State private var showingJumpConfirm = false

    /// Seeded from `WorkoutSessionService.autostartsRunning` — once true (whether from
    /// autostart or a tapped play button), stays true for the rest of the section; only
    /// entering the section for the very first pass is gated, not every repeat of it.
    @State private var isRunning: Bool

    /// When the current step ends, or nil when the countdown is stopped.
    ///
    /// A wall-clock deadline rather than a per-tick decrement: the ticker doesn't run
    /// while the app is backgrounded, so counting ticks meant a step froze when the user
    /// switched apps and resumed from where it stopped instead of catching up.
    @State private var stepEndsAt: Date?

    /// The exercise to name as this section runs out, or nil when nothing continues past
    /// it. Supplied by `SessionRunnerView`, which is the only level that can see sibling
    /// sections. Evaluated at the moment of the cue, not at init — a lookahead computed
    /// early would answer for the wrong pass.
    let upNext: () -> String?

    /// Counting down the breather between two passes. The section's last step is finished
    /// and logged; only the clock is still running.
    @State private var isSectionResting = false

    init(session: WorkoutSession, section: WorkoutSection, cues: TimerCueSettings, upNext: @escaping () -> String? = { nil }, onSectionComplete: @escaping () -> Void) {
        self.session = session
        self.section = section
        self.cues = cues
        self.upNext = upNext
        self.onSectionComplete = onSectionComplete
        _isRunning = State(initialValue: WorkoutSessionService.autostartsRunning(session, section: section))
    }

    /// What this pass actually plays — a Get Ready of 0, or one that doesn't repeat, is
    /// gone rather than present-and-instant. Every index in this view, the scrub strip and
    /// `StepLog.sortOrder` is relative to this array, so they stay consistent with each
    /// other as long as they all read it.
    private var steps: [TimeSectionStep] { section.runnableTimeSteps(pass: currentRepeat) }
    private var currentIndex: Int { session.currentStepIndex ?? 0 }
    private var currentStep: TimeSectionStep? {
        guard currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    /// The step clock runs only when the section is playing *and* the workout as a whole
    /// is running — pausing either freezes it.
    private var isCountingDown: Bool { isRunning && session.status == .inProgress }

    private var timerHeightFraction: CGFloat { horizontalSizeClass == .regular ? 0.45 : 0.3 }

    /// The step's color, filling the timer area the same solid way the scrub strip
    /// fills its active chip. Always present now that "never chosen" resolves to a
    /// real selection — green for an exercise, gray for Rest/Get Ready.
    private var timerTint: Color {
        if isSectionResting { return PaletteColor.gray.color }
        return currentStep?.resolvedColor.color ?? Color.appAccent
    }

    /// Gray is a mid-tone, where white text washes out — everything else in the
    /// palette is deep enough to carry it.
    private var timerForeground: Color {
        if isSectionResting { return Color.appInk }
        return currentStep?.resolvedColor == .gray ? Color.appInk : .white
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
                // The only place speech is set up. Creating the synthesizer and warming
                // the audio session here rather than on the first cue is what keeps the
                // opening word of a step name from being clipped; `SessionRunnerView`
                // tears it back down on the way out of the workout.
                SpeechAnnouncer.prepare()
                beginStep(seconds: currentStep.durationSeconds)
            }
            .onChange(of: currentIndex) { _, _ in
                beginStep(seconds: self.currentStep?.durationSeconds ?? 0)
            }
            .onChange(of: isCountingDown) { _, _ in syncCountdown() }
            .onDisappear { SpeechAnnouncer.stop() }
            // Stops outright while the section or the workout is paused, instead of
            // ticking and discarding the tick inside the handler.
            .secondTicker(isActive: isCountingDown) { tick() }
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

    /// What you last held this at, when the step names weighted equipment and a record
    /// exists. The Follow Along counterpart to the rep runner's `recordLine`, and the
    /// whole point of recording the weight in the first place — a fixed-duration step
    /// otherwise gives you nothing to aim at.
    ///
    /// Under the name rather than in `timerArea`: that block is one tap target for
    /// pause/resume, and hanging a second thing off it is the trap `RestTimerView` hit.
    @ViewBuilder
    private func recordLine(_ step: TimeSectionStep, exercise: Exercise) -> some View {
        if let equipment = recordEquipment(for: step, exercise: exercise),
           let record = PersonalRecordQueries.current(
               for: exercise,
               equipment: equipment,
               executionType: PersonalRecordQueries.resolvedExecutionType(step.executionType, for: exercise),
               trackingMode: .maxHoldTime,
               isBodyweight: false,
               isFollowAlong: true,
               context: context
           ),
           record.weight != nil {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
                Text("\(PersonalRecordFormatting.summary(record)) · \(equipment.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// The step's own equipment choice, validated against the exercise's live weighted
    /// options — the same fallback `chosenEquipment` performs on the rep side, so a stale
    /// reference reads a real record rather than none.
    private func recordEquipment(for step: TimeSectionStep, exercise: Exercise) -> Equipment? {
        guard !step.prefersBodyweight else { return nil }
        let options = exercise.weightedEquipmentOptions
        guard !options.isEmpty else { return nil }
        let id = step.preferredEquipment?.id ?? exercise.defaultWeightedEquipment?.id
        return options.first { $0.id == id } ?? options.first
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
            // The between-passes rest borrows the ordinary rest's face — it is the same
            // thing to the person doing it, and inventing a second one would only make
            // them look at two designs for one idea.
            if isSectionResting {
                statusLabel("pause.circle.fill", "Rest")
            } else {
                switch step.stepType {
                case .exercise:
                    if let exercise = step.exercise {
                        if ExerciseMediaView.hasMedia(exercise) {
                            // Unchanged from before: fixed box, `.title` name beneath it.
                            ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: min(30, Double(step.durationSeconds))), fillsWidth: true)
                                .id(exercise.id)
                                .padding(.horizontal)
                            Text(step.displayTitle)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                            recordLine(step, exercise: exercise)
                        } else {
                            // Nothing to show, so the placeholder box is dropped entirely
                            // and the name takes the freed space.
                            Text(step.displayTitle)
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.4)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 24)
                            recordLine(step, exercise: exercise)
                        }
                        ExerciseVideoButton(exercise: exercise)
                            .id(exercise.id)
                            .padding(.horizontal)
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

    /// What a step is called out loud, before the execution type is folded in.
    ///
    /// Deliberately *not* `step.displayTitle`: that already appends the type, and
    /// `spokenLabel` below has its own rule for when to say it — only the type is spoken
    /// when it's the sole thing that changed between two steps.
    private func spokenName(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    /// What a step is called out loud, given what came before it.
    ///
    /// The whole of the rule: when two consecutive steps are the same exercise differing
    /// only in side or in execution type, only the part that changed is spoken. Hearing
    /// "Split Squat" again tells the listener nothing they don't already know — "Right" is
    /// the only thing that actually changed, and it's what they need in the second before
    /// it starts. Alternating sides is the case this exists for.
    private func spokenLabel(for step: TimeSectionStep, following previous: TimeSectionStep?) -> String {
        if let previous,
           step.stepType == .exercise, previous.stepType == .exercise,
           let exerciseID = step.exercise?.id, exerciseID == previous.exercise?.id {
            let sideChanged = step.side != previous.side
            let typeChanged = step.executionType?.id != previous.executionType?.id
            // Only when it's the *sole* difference — if both moved, the full name is the
            // honest thing to say.
            if sideChanged, !typeChanged, let side = step.side {
                // Long form: spoken on its own, "Left" could be heard as an instruction
                // or a direction rather than as which side is next.
                return side.longLabel
            }
            if typeChanged, !sideChanged, let type = step.executionType {
                return type.name
            }
        }
        let name = spokenName(for: step)
        guard step.stepType == .exercise else { return name }
        return ExerciseNaming.title(name, side: step.side, executionType: step.executionType)
    }

    /// "Next: Push Up", optionally followed by "Ten seconds left", at the configured mark.
    ///
    /// Skipped on steps barely longer than the cue itself, where it would land almost on
    /// top of the step-start announcement — the old rule, now derived from the configured
    /// seconds instead of a hardcoded 12 against a hardcoded 10.
    private func announceNextIfNeeded() {
        guard AppSettings.speechEnabled, AppSettings.voiceAnnounceNextEnabled else { return }
        let mark = AppSettings.voiceAnnounceNextSeconds
        guard remainingSeconds == mark else { return }
        // Measured against whatever phase is actually running: during a between-passes
        // rest the current step is the one that just finished, and its length says
        // nothing about how long there is left to speak into.
        let phaseSeconds = isSectionResting
            ? section.sectionRest(after: currentRepeat)
            : (currentStep?.durationSeconds ?? 0)
        guard phaseSeconds >= mark + 2 else { return }

        // Time first, then what's coming: "ten seconds left" is the cue to start winding
        // down, and hearing it after the next exercise's name means acting on it a beat
        // late. The name is also the half worth having last, since it is what you carry
        // into the next step.
        var parts: [String] = []
        if AppSettings.voiceTimeLeftEnabled {
            parts.append("\(mark) second\(mark == 1 ? "" : "s") left")
        }
        let nextIndex = currentIndex + 1
        if nextIndex < steps.count, !isSectionResting, let currentStep {
            parts.append("Next: \(spokenLabel(for: steps[nextIndex], following: currentStep))")
        } else if !isSectionResting, section.sectionRest(after: currentRepeat) > 0 {
            // The pass is over but the next thing is the breather, not the exercise after
            // it. Naming the exercise here would announce something two phases away — the
            // rest's own cue names it, ten seconds before the rest ends.
            parts.append("Next: Rest")
        } else if let name = upNext() {
            // Nothing left in this pass, but something continues past it — another pass of
            // this section, or another Follow Along. Naming it keeps the countdown reading
            // as one motion rather than stopping dead at the section boundary.
            parts.append("Next: \(name)")
        } else {
            parts.append(endOfSectionPhrase)
        }
        guard !parts.isEmpty else { return }
        SpeechAnnouncer.speak(parts.joined(separator: ". "))
    }

    /// The last few seconds, one number per tick.
    ///
    /// Independent of the announcement above rather than part of it: the two answer
    /// different questions ("what's coming" vs "how long now"), and pinning the countdown
    /// to whatever time happened to be left after an utterance finished would make its
    /// length depend on the speed of the chosen voice.
    private func announceCountdownIfNeeded() {
        guard AppSettings.speechEnabled, AppSettings.voiceCountdownEnabled else { return }
        guard remainingSeconds > 0, remainingSeconds <= AppSettings.voiceCountdownFromSeconds else { return }
        // Not on the same tick as the announcement — a number cutting off "Next: Push Up"
        // mid-word is worse than skipping one count.
        guard !(AppSettings.voiceAnnounceNextEnabled && remainingSeconds == AppSettings.voiceAnnounceNextSeconds) else { return }
        SpeechAnnouncer.speak("\(remainingSeconds)")
    }

    /// A named section is worth saying; an unnamed one falls back to
    /// `"Follow Along Section"`, and "End section Follow Along Section" is not a sentence.
    private var endOfSectionPhrase: String {
        guard let name = section.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return "End of section" }
        return "End section, \(name)"
    }

    private func announceCurrentStep() {
        guard AppSettings.speechEnabled, AppSettings.voiceAnnounceStartEnabled else { return }
        if isSectionResting {
            SpeechAnnouncer.speak("Rest")
            return
        }
        guard let currentStep else { return }
        let previous = currentIndex > 0 ? steps[currentIndex - 1] : nil
        SpeechAnnouncer.speak(spokenLabel(for: currentStep, following: previous))
    }

    // MARK: - Step clock

    /// Resets the countdown for a step and starts it if the section is playing.
    private func beginStep(seconds: Int) {
        remainingSeconds = seconds
        stepEndsAt = nil
        syncCountdown()
        announceCurrentStep()
    }

    /// Rebases the deadline when the section or the workout starts or stops. Pausing
    /// freezes what's left; resuming counts from there, so paused time isn't spent.
    private func syncCountdown() {
        if isCountingDown {
            guard stepEndsAt == nil else { return }
            stepEndsAt = Date.now.addingTimeInterval(Double(remainingSeconds))
        } else {
            guard stepEndsAt != nil else { return }
            remainingSeconds = liveRemaining()
            stepEndsAt = nil
        }
    }

    /// Seconds left according to the clock, or the frozen display value when stopped.
    private func liveRemaining() -> Int {
        guard let stepEndsAt else { return remainingSeconds }
        return max(0, Int(stepEndsAt.timeIntervalSinceNow.rounded(.up)))
    }

    private func tick() {
        guard stepEndsAt != nil else { return }
        let previous = remainingSeconds
        let current = liveRemaining()

        if current <= 0 {
            remainingSeconds = 0
            stepEndsAt = nil
            completeCurrentStep()
            return
        }

        guard current != previous else { return }
        remainingSeconds = current
        // Cues only on a normal one-second step. Returning from a suspended app the
        // countdown jumps, and a beep or a "ten seconds left" for a threshold that passed
        // while the app was in the background would land late and mean nothing.
        guard previous - current == 1 else { return }
        SoundPlayer.playWarningIfNeeded(remainingSeconds: current, cues: cues)
        announceNextIfNeeded()
        announceCountdownIfNeeded()
    }

    private func completeCurrentStep() {
        if isSectionResting {
            SoundPlayer.playTimerCompleteIfNeeded(cues: cues)
            isSectionResting = false
            onSectionComplete()
            return
        }
        guard let currentStep else { return }
        SoundPlayer.playTimerCompleteIfNeeded(cues: cues)
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
            executionType: step.executionType,
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
            return
        }
        session.markDirty()
        try? context.save()

        // Played at the tail of the pass that just finished, not the head of the next
        // one: `SessionRunnerView` keys this view on the pass, so there is no "next pass"
        // instance yet to run it in.
        let rest = section.sectionRest(after: currentRepeat)
        guard rest > 0 else {
            onSectionComplete()
            return
        }
        isSectionResting = true
        beginStep(seconds: rest)
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
