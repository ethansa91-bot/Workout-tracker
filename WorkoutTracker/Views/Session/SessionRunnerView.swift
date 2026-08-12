import SwiftUI
import SwiftData
import Combine

struct SessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let soundProfile: TimerSoundProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingPauseSheet = false
    @State private var showingStopConfirm = false
    @State private var showingSummary = false
    @State private var elapsedDisplay = "0:00:00"

    // Must be @State, not `let` — see TimeSessionRunnerView for why.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var workout: Workout? { session.workout }
    private var blocks: [WorkoutBlock] { workout?.sortedBlocks ?? [] }
    private var currentBlock: WorkoutBlock? {
        guard session.currentBlockIndex >= 0, session.currentBlockIndex < blocks.count else { return nil }
        return blocks[session.currentBlockIndex]
    }

    var body: some View {
        Group {
            if let currentBlock {
                Group {
                    if currentBlock.blockType == .time {
                        TimeSessionRunnerView(session: session, block: currentBlock, soundProfile: soundProfile, onBlockComplete: advanceBlock)
                    } else {
                        RepSessionRunnerView(session: session, block: currentBlock, soundProfile: soundProfile, onBlockComplete: advanceBlock)
                    }
                }
                .id(currentBlock.id)
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    pauseSession()
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showingStopConfirm = true
                } label: {
                    Label("Stop", systemImage: "xmark.circle")
                }
            }
        }
        .onReceive(ticker) { _ in updateElapsedDisplay() }
        .onAppear { updateElapsedDisplay() }
        .sheet(isPresented: $showingPauseSheet) {
            pauseSheet
        }
        .confirmationDialog("End this workout as unfinished?", isPresented: $showingStopConfirm, titleVisibility: .visible) {
            Button("End as Unfinished", role: .destructive) { stopSession() }
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
            HStack {
                Text(elapsedDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progressFraction * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.appSurface)
    }

    private var pauseSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Workout Paused")
                .font(.title2.bold())

            Button {
                resumeSession()
            } label: {
                Text("Resume").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Exit — Resume Later") {
                showingPauseSheet = false
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("End as Unfinished", role: .destructive) {
                stopSession()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .interactiveDismissDisabled()
    }

    private var totalItems: Int {
        blocks.reduce(0) { $0 + itemCount(in: $1) }
    }

    private func itemCount(in block: WorkoutBlock) -> Int {
        block.blockType == .time ? block.sortedTimeSteps.count : block.sortedRepExercises.count
    }

    private var progressFraction: Double {
        guard totalItems > 0 else { return 0 }
        var completed = blocks.prefix(session.currentBlockIndex).reduce(0) { $0 + itemCount(in: $1) }
        if let currentBlock {
            completed += currentBlock.blockType == .time ? (session.currentStepIndex ?? 0) : (session.currentExerciseIndex ?? 0)
        }
        return min(1, Double(completed) / Double(totalItems))
    }

    private func updateElapsedDisplay() {
        let total = Int(session.elapsedSeconds)
        elapsedDisplay = String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func advanceBlock() {
        guard let workout else { return }
        WorkoutSessionService.advanceBlock(session, workout: workout, context: context)
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
