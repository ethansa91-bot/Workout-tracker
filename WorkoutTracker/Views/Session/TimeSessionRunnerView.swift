import SwiftUI
import SwiftData
import Combine

struct TimeSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let block: WorkoutBlock
    let soundProfile: TimerSoundProfile
    let onBlockComplete: () -> Void

    @Environment(\.modelContext) private var context

    @State private var remainingSeconds: Int = 0
    @State private var pendingJumpIndex: Int?
    @State private var showingJumpConfirm = false

    // Must be @State, not `let` — a plain `let` gets recomputed (a brand new Timer)
    // every time this View struct is reinitialized, which happens on every re-render
    // (i.e. every tick), so the timer rarely survives long enough to actually fire.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var steps: [TimeBlockStep] { block.sortedTimeSteps }
    private var currentIndex: Int { session.currentStepIndex ?? 0 }
    private var currentStep: TimeBlockStep? {
        guard currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }
    private var nextStep: TimeBlockStep? {
        let next = currentIndex + 1
        guard next < steps.count else { return nil }
        return steps[next]
    }

    var body: some View {
        if let currentStep {
            VStack(spacing: 20) {
                mainStepView(currentStep)
                nextStepPreview
                SessionScrubStripView(
                    steps: steps,
                    currentIndex: currentIndex,
                    completedIndices: completedIndices,
                    onSelect: requestJump
                )
            }
            .padding(.vertical)
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
            Color.clear.onAppear { onBlockComplete() }
        }
    }

    private func mainStepView(_ step: TimeBlockStep) -> some View {
        VStack(spacing: 12) {
            switch step.stepType {
            case .exercise:
                Image(systemName: step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(step.exercise?.name ?? "Exercise")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
            case .rest:
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Rest")
                    .font(.title.bold())
            case .getReady:
                Image(systemName: "hourglass")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Get Ready")
                    .font(.title.bold())
            }
            Text(timeString(remainingSeconds))
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var nextStepPreview: some View {
        if let nextStep {
            HStack {
                Image(systemName: nextStepIcon(nextStep))
                    .foregroundStyle(.secondary)
                Text("Next: \(nextStepTitle(nextStep))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nextStep.durationSeconds)s").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        } else {
            Text("Last step in this block")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func nextStepIcon(_ step: TimeBlockStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional"
        case .rest: return "pause.circle"
        case .getReady: return "hourglass"
        }
    }

    private func nextStepTitle(_ step: TimeBlockStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.name ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    private var completedIndices: Set<Int> {
        Set(session.stepLogs.compactMap { log -> Int? in
            guard let step = log.timeBlockStep else { return nil }
            return steps.firstIndex(where: { $0.id == step.id })
        })
    }

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
        guard session.status == .inProgress else { return }
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

    private func logStep(_ step: TimeBlockStep, outcome: StepOutcome, actualDuration: Int) {
        guard !session.stepLogs.contains(where: { $0.timeBlockStep?.id == step.id }) else { return }
        let log = StepLog(
            session: session,
            timeBlockStep: step,
            stepExerciseNameSnapshot: step.exercise?.name,
            plannedDurationSeconds: step.durationSeconds,
            actualDurationSeconds: max(0, actualDuration),
            outcome: outcome,
            sortOrder: steps.firstIndex(where: { $0.id == step.id }) ?? 0
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
            onBlockComplete()
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
            for log in session.stepLogs where log.timeBlockStep.map({ idsToClear.contains($0.id) }) ?? false {
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
