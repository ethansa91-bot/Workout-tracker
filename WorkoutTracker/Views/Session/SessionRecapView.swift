import SwiftUI
import SwiftData

private struct SessionOverviewItem: Identifiable {
    let id: UUID
    let iconName: String
    let title: String
    let detail: String
}

/// Tapping a workout in the list lands here: a quick recap of everything in it, plus
/// the ability to start it (or resume a paused session, or jump into editing).
struct SessionRecapView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context

    @State private var activeSession: WorkoutSession?
    @State private var showingSupersedeConfirm = false
    @State private var sessionSoundProfile: TimerSoundProfile?

    private var activeSoundProfile: TimerSoundProfile {
        sessionSoundProfile ?? AppSettings.timerSoundProfile
    }

    private var isLocked: Bool { workout.isLocked }
    private var pausedSession: WorkoutSession? {
        workout.sessions.first { $0.status == .paused }
    }
    /// Every block must contain at least one exercise — a workout with even a single
    /// empty block isn't ready to start, not just a workout with zero blocks.
    private var allBlocksReady: Bool {
        !workout.sortedBlocks.isEmpty && workout.sortedBlocks.allSatisfy { block in
            block.blockType == .time
                ? block.sortedTimeSteps.contains { $0.stepType == .exercise }
                : !block.sortedRepExercises.isEmpty
        }
    }

    var body: some View {
        List {
            Section {
                heroCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(workout.sortedBlocks) { block in
                Section(blockTitle(block)) {
                    ForEach(overviewItems(for: block)) { item in
                        overviewItemRow(item)
                    }
                }
            }
            if !allBlocksReady {
                Text("Every block needs at least one exercise before this workout can be started.")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .themedListBackground()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLocked {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        destinationView(for: .editing(workout))
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            startControls
        }
        .navigationDestination(item: $activeSession) { session in
            SessionRunnerView(session: session, soundProfile: activeSoundProfile)
        }
        .confirmationDialog(
            "Starting a new session will mark your paused session as unfinished — it can't be resumed afterward. Continue?",
            isPresented: $showingSupersedeConfirm,
            titleVisibility: .visible
        ) {
            Button("Start New", role: .destructive) { startNewSession() }
        }
    }

    @ViewBuilder
    private var startControls: some View {
        if let pausedSession {
            VStack(spacing: 8) {
                soundProfilePicker
                Button {
                    resumeSession(pausedSession)
                } label: {
                    Text("Resume Workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Start New Instead", role: .destructive) {
                    showingSupersedeConfirm = true
                }
                .font(.footnote)
            }
            .padding()
            .background(Color.appSurface)
        } else if allBlocksReady {
            VStack(spacing: 8) {
                soundProfilePicker
                Button {
                    startNewSession()
                } label: {
                    Text("Start Workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.appSurface)
        }
    }

    private var soundProfilePicker: some View {
        Menu {
            ForEach(TimerSoundProfile.allCases) { profile in
                Button {
                    sessionSoundProfile = profile
                } label: {
                    if profile == activeSoundProfile {
                        Label(profile.label, systemImage: "checkmark")
                    } else {
                        Text(profile.label)
                    }
                }
            }
        } label: {
            HStack {
                Label("Timer sound", systemImage: "speaker.wave.2")
                Spacer()
                Text(activeSoundProfile.label)
                    .foregroundStyle(Color.appInkMuted)
            }
            .font(.footnote)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heroStat)
                .font(.appSerif(.title2))
                .foregroundStyle(Color.appInk)
            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardStyle()
    }

    private var heroStat: String {
        let blockCount = workout.sortedBlocks.count
        let exerciseCount = workout.sortedBlocks.reduce(0) { total, block in
            total + (block.blockType == .time
                ? block.sortedTimeSteps.filter { $0.stepType == .exercise }.count
                : block.sortedRepExercises.count)
        }
        return "\(blockCount) Block\(blockCount == 1 ? "" : "s") · \(exerciseCount) Exercise\(exerciseCount == 1 ? "" : "s")"
    }

    private var heroSubtitle: String {
        "\(workout.displayType.rawValue.capitalized) workout"
    }

    @ViewBuilder
    private func destinationView(for destination: WorkoutEditDestination) -> some View {
        switch destination {
        case .workout(let workout):
            WorkoutEditorView(workout: workout)
        case .block(let block):
            BlockEditorView(block: block)
        }
    }

    private func startNewSession() {
        activeSession = WorkoutSessionService.startNewSession(for: workout, context: context)
    }

    private func resumeSession(_ session: WorkoutSession) {
        WorkoutSessionService.resume(session, context: context)
        activeSession = session
    }

    private func blockTitle(_ block: WorkoutBlock) -> String {
        if let name = block.name, !name.isEmpty { return name }
        return block.blockType == .time ? "Time Block" : "Rep Block"
    }

    private func overviewItems(for block: WorkoutBlock) -> [SessionOverviewItem] {
        if block.blockType == .time {
            return block.sortedTimeSteps.map { step in
                SessionOverviewItem(
                    id: step.id,
                    iconName: overviewIcon(for: step),
                    title: overviewTitle(for: step),
                    detail: "\(step.durationSeconds)s"
                )
            }
        } else {
            return block.sortedRepExercises.map { entry in
                SessionOverviewItem(
                    id: entry.id,
                    iconName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional",
                    title: entry.exercise?.name ?? "Exercise",
                    detail: "\(entry.targetSets) sets · rest \(entry.customRestSeconds.map { "\($0)s" } ?? "default")"
                )
            }
        }
    }

    private func overviewIcon(for step: TimeBlockStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional"
        case .rest: return "pause.circle"
        case .getReady: return "hourglass"
        }
    }

    private func overviewTitle(for step: TimeBlockStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.name ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    private func overviewItemRow(_ item: SessionOverviewItem) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: item.iconName, size: 28)
            Text(item.title)
            Spacer()
            Text(item.detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.appRust)
        }
        .padding(.vertical, 2)
    }
}
