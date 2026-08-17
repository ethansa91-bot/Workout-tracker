import SwiftUI
import SwiftData
import Combine

struct SessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let soundProfile: TimerSoundProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingPauseSheet = false
    @State private var showingSummary = false
    @State private var elapsedDisplay = "0:00:00"

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                        TimeSessionRunnerView(session: session, section: currentSection, soundProfile: soundProfile, onSectionComplete: advanceSection)
                    case .rep:
                        RepSessionRunnerView(session: session, section: currentSection, soundProfile: soundProfile, onSectionComplete: advanceSection)
                    case .emom:
                        EmomSessionRunnerView(session: session, section: currentSection, soundProfile: soundProfile, onSectionComplete: advanceSection)
                    case .amrap:
                        AmrapSessionRunnerView(session: session, section: currentSection, soundProfile: soundProfile, onSectionComplete: advanceSection)
                    }
                }
                .id(currentSection.id)
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
        .toolbar {
            if !showingPauseSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pauseSession()
                    } label: {
                        Label("Pause", systemImage: "pause.circle")
                    }
                }
            }
        }
        .onReceive(ticker) { _ in updateElapsedDisplay() }
        .onAppear { updateElapsedDisplay() }
        .overlay {
            if showingPauseSheet {
                pauseOverlay
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
                Text(elapsedDisplay)
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

                VStack(spacing: 12) {
                    Button("Exit — Resume Later") {
                        showingPauseSheet = false
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button("End as Unfinished", role: .destructive) {
                        stopSession()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.appDanger)
                }
            }
            .padding(32)
        }
    }

    private var totalItems: Int {
        sections.reduce(0) { $0 + itemCount(in: $1) }
    }

    private func itemCount(in section: WorkoutSection) -> Int {
        switch section.sectionType {
        case .time: return section.sortedTimeSteps.count
        case .rep: return section.sortedRepExercises.count
        case .emom: return section.emomRoundCount
        // A single countdown, not a list of items — counted as one unit of progress.
        case .amrap: return 1
        }
    }

    /// Items completed across every section before the current one, plus progress
    /// into the current section — the same whole-workout count that drives both the
    /// progress bar and the "Exercise X of Y" counter, so the two always agree.
    private var completedItems: Int {
        var completed = sections.prefix(session.currentSectionIndex).reduce(0) { $0 + itemCount(in: $1) }
        if let currentSection {
            switch currentSection.sectionType {
            case .time, .emom: completed += session.currentStepIndex ?? 0
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

    private func updateElapsedDisplay() {
        let total = Int(session.elapsedSeconds)
        elapsedDisplay = String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
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

    private func stopSession() {
        WorkoutSessionService.abandon(session, context: context)
        showingPauseSheet = false
        dismiss()
    }
}
