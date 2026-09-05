import SwiftUI
import SwiftData

struct SessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let cues: TimerCueSettings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingPauseSheet = false
    @State private var showingDeleteConfirm = false
    @State private var showingExerciseList = false
    @State private var showingSummary = false

    private var workout: Workout? { session.workout }
    private var sections: [WorkoutSection] { workout?.sortedSections ?? [] }
    private var currentSection: WorkoutSection? {
        guard session.currentSectionIndex >= 0, session.currentSectionIndex < sections.count else { return nil }
        return sections[session.currentSectionIndex]
    }

    var body: some View {
        Group {
            if let currentSection {
                Group {
                    switch currentSection.sectionType {
                    case .time:
                        TimeSessionRunnerView(session: session, section: currentSection, cues: cues, upNext: upNextExerciseName, onSectionComplete: advanceSection)
                    case .rep:
                        RepSessionRunnerView(session: session, section: currentSection, cues: cues, onSectionComplete: advanceSection)
                    case .emom:
                        EmomSessionRunnerView(session: session, section: currentSection, cues: cues, onSectionComplete: advanceSection)
                    case .amrap:
                        AmrapSessionRunnerView(session: session, section: currentSection, cues: cues, onSectionComplete: advanceSection)
                    }
                }
                // Includes the repeat so each pass rebuilds the runner — state seeded
                // once in `init`/`.onAppear` (EMOM's autostart, AMRAP's hasStarted)
                // would otherwise never re-initialize on the next round.
                .id("\(currentSection.id)-\(session.currentSectionRepeat ?? 0)")
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        // Only while actually working out — a paused session should let the screen
        // sleep normally.
        .keepScreenAwake(session.status == .inProgress)
        .toolbar {
            if !showingPauseSheet {
                // Pause on the left, the exercise list on the right — the panel's own
                // close button then sits on the same side as this one.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        pauseSession()
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingExerciseList.toggle()
                        }
                    } label: {
                        Label("All Exercises", systemImage: "line.3.horizontal")
                    }
                }
            }
        }
        // The one place speech is released: `TimeSessionRunnerView` can come and go
        // between sections within a single workout, so tearing the synthesizer down there
        // would rebuild it on every Follow Along section. Leaving the runner ends the
        // workout's claim on it, and on the audio session with it.
        .onDisappear { SpeechAnnouncer.teardown() }
        .overlay {
            if showingPauseSheet {
                pauseOverlay
            }
        }
        // An overlay rather than a sheet, for the same reason `pauseOverlay` is one:
        // the workout stays on screen beside it instead of being covered.
        .overlay {
            if showingExerciseList, let workout {
                SessionExerciseListView(
                    session: session,
                    sections: workout.sortedSections,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingExerciseList = false
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .fullScreenCover(isPresented: $showingSummary) {
            if let workout {
                SessionSummaryView(session: session, workout: workout) {
                    dismiss()
                }
            }
        }
        .onChange(of: session.status) { _, newValue in
            if newValue == .finished {
                showingSummary = true
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: progressFraction)
                .tint(.accentColor)
            // Three equal thirds (not a single HStack + Spacer) so the middle counter
            // sits truly centered in the bar regardless of how wide the elapsed-time
            // and percent text on either side are.
            HStack {
                ElapsedTimeLabel(session: session)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Exercise \(currentItemNumber) of \(totalItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("\(Int(progressFraction * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(Color.appSurface)
    }

    private static let pauseButtonHeight: CGFloat = 28
    private static let pauseButtonCornerRadius: CGFloat = 12

    // A translucent overlay, not a sheet — the paused session stays visible
    // (dimmed) behind it instead of being fully covered. No dismiss path except
    // its own three buttons; tapping the dimmed background does nothing, same
    // guarantee `.interactiveDismissDisabled()` gave the sheet this replaced.
    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Workout Paused")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Button {
                    resumeSession()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 72))
                }
                .tint(.white)

                // Solid fills, not `.bordered` glass: over the 75% black scrim a
                // translucent button reads as washed out rather than as a real choice.
                // Both labels take the full width and a fixed height rather than sizing
                // to their own (very different length) text, so the two choices read as
                // an evenly weighted pair instead of one wide button above a narrow one.
                VStack(spacing: 12) {
                    Button {
                        showingPauseSheet = false
                        dismiss()
                    } label: {
                        Text("Exit — Resume Later")
                            .frame(maxWidth: .infinity, minHeight: Self.pauseButtonHeight)
                    }
                    .tint(Color.appAccent)

                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Exit and Delete Session")
                            .frame(maxWidth: .infinity, minHeight: Self.pauseButtonHeight)
                    }
                    .tint(Color.appDanger)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: Self.pauseButtonCornerRadius))
                .controlSize(.large)
                .foregroundStyle(.white)
                // Capped so the pair stays a readable block on iPad instead of
                // stretching the full width of the scrim.
                .frame(maxWidth: 340)
            }
            .padding(32)
        }
        // A hard delete takes the session's set and step logs with it, so it can't sit
        // one stray tap away.
        .confirmationDialog(
            "Delete this session? Everything logged in it will be lost.",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Session", role: .destructive) { deleteSession() }
        }
    }

    private var totalItems: Int {
        sections.reduce(0) { $0 + itemCount(in: $1) }
    }

    /// Items in one pass of the section — see `itemCount(in:)` for the repeat-aware
    /// total that the progress bar uses.
    private func itemsPerPass(in section: WorkoutSection, pass: Int = 0) -> Int {
        switch section.sectionType {
        // Per pass, not a constant: a Get Ready that doesn't repeat makes the first pass
        // one step longer than the rest.
        case .time: return section.runnableTimeSteps(pass: pass).count
        case .rep: return section.sortedRepExercises.count
        // A to-failure section has no round count to measure against, so it is one unit
        // like AMRAP — a bar filling towards a total that doesn't exist would be a lie.
        case .emom: return section.emomToFailure ? 1 : section.emomRoundCount
        // A single countdown, not a list of items — counted as one unit of progress.
        case .amrap: return 1
        }
    }

    /// Multiplied by the repeat count, or the bar would read 100% partway through a
    /// repeated section's second pass.
    private func itemCount(in section: WorkoutSection) -> Int {
        (0..<section.effectiveRepeatCount).reduce(0) { $0 + itemsPerPass(in: section, pass: $1) }
    }

    /// Items completed across every section before the current one, plus progress
    /// into the current section — the same whole-workout count that drives both the
    /// progress bar and the "Exercise X of Y" counter, so the two always agree.
    private var completedItems: Int {
        var completed = sections.prefix(session.currentSectionIndex).reduce(0) { $0 + itemCount(in: $1) }
        if let currentSection {
            // Passes already finished in this section count in full — each at its own
            // length, since the first may have carried a count-in the others don't.
            let pass = session.currentSectionRepeat ?? 0
            completed += (0..<pass).reduce(0) { $0 + itemsPerPass(in: currentSection, pass: $1) }
            switch currentSection.sectionType {
            case .time: completed += session.currentStepIndex ?? 0
            // Rounds only count towards the bar when there is a total to count towards;
            // a to-failure section stays one unfinished unit, exactly like AMRAP.
            case .emom: completed += currentSection.emomToFailure ? 0 : (session.currentStepIndex ?? 0)
            case .rep: completed += session.currentExerciseIndex ?? 0
            case .amrap: break // stays a single unit until the countdown finishes
            }
        }
        return completed
    }

    private var progressFraction: Double {
        guard totalItems > 0 else { return 0 }
        return min(1, Double(completedItems) / Double(totalItems))
    }

    /// 1-indexed position for display — "completed" items plus the one currently in
    /// progress, capped at the total so the last exercise reads e.g. "20 of 20" rather
    /// than "21 of 20".
    private var currentItemNumber: Int {
        min(completedItems + 1, max(totalItems, 1))
    }

    /// The exercise the voice should name as a Follow Along section runs out — but only
    /// when what follows actually continues: another pass of the same section, or another
    /// Follow Along. nil means the runner should announce the end of the section instead,
    /// which is the honest thing to say before a rep section or the end of the workout.
    private func upNextExerciseName() -> String? {
        guard let workout else { return nil }
        let next: WorkoutSection
        switch WorkoutSessionService.lookahead(session, workout: workout) {
        case .anotherPass(let section):
            next = section
        case .nextSection(let section):
            guard section.sectionType == .time else { return nil }
            next = section
        case .endOfWorkout:
            return nil
        }
        // The first *exercise*, not the first step: a count-in or a rest is not what you
        // need to hear coming.
        let pass = next.id == currentSection?.id ? (session.currentSectionRepeat ?? 0) + 1 : 0
        return next.runnableTimeSteps(pass: pass)
            .first { $0.stepType == .exercise }
            .map { ExerciseNaming.title($0.exercise, side: $0.side, executionType: $0.executionType) }
    }

    private func advanceSection() {
        guard let workout else { return }
        WorkoutSessionService.advanceSection(session, workout: workout, context: context)
    }

    private func pauseSession() {
        WorkoutSessionService.pause(session, context: context)
        showingPauseSheet = true
    }

    private func resumeSession() {
        WorkoutSessionService.resume(session, context: context)
        showingPauseSheet = false
    }

    private func deleteSession() {
        showingPauseSheet = false
        WorkoutSessionService.delete(session, context: context)
        dismiss()
    }
}
