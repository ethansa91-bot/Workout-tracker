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
    @State private var showingRenamePrompt = false
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive
    @State private var blockPendingDeletion: WorkoutBlock?
    @State private var manageExercisesBlock: WorkoutBlock?
    @State private var showingDescriptionEditor = false
    @State private var descriptionText = ""

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

            Section {
                if !isLocked && workout.kind == .personalized {
                    blockListControls
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(workout.sortedBlocks) { block in
                    blockCard(block)
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: reorderAction)
            }

            if !allBlocksReady {
                Text("Every block needs at least one exercise before this workout can be started.")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                    .listRowBackground(Color.clear)
            }
        }
        .themedListBackground()
        .environment(\.editMode, $editMode)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            startControls
        }
        .navigationDestination(item: $activeSession) { session in
            SessionRunnerView(session: session, soundProfile: activeSoundProfile)
        }
        .navigationDestination(item: $manageExercisesBlock) { block in
            BlockEditorView(block: block)
        }
        .confirmationDialog(
            "Starting a new session will mark your paused session as unfinished — it can't be resumed afterward. Continue?",
            isPresented: $showingSupersedeConfirm,
            titleVisibility: .visible
        ) {
            Button("Start New", role: .destructive) { startNewSession() }
        }
        .confirmationDialog(
            "Delete \"\(blockPendingDeletion.map { blockTitle($0) } ?? "")\"? Its exercises will be removed too.",
            isPresented: Binding(
                get: { blockPendingDeletion != nil },
                set: { if !$0 { blockPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDeleteBlock() }
        }
        .alert("Rename Workout", isPresented: $showingRenamePrompt) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameWorkout() }
        }
        .sheet(isPresented: $showingDescriptionEditor) {
            descriptionEditorSheet
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
                .tint(Color.appDanger)
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
            HStack(spacing: 8) {
                Text(workout.name)
                    .font(.appSerif(.title2))
                    .foregroundStyle(Color.appInk)
                if !isLocked {
                    Button {
                        renameText = workout.name
                        showingRenamePrompt = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appInkMuted)
                }
            }
            Text(heroInfoLine)
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)

            descriptionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardStyle()
    }

    @ViewBuilder
    private var descriptionRow: some View {
        if let notes = workout.notes, !notes.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                if !isLocked {
                    Button {
                        descriptionText = notes
                        showingDescriptionEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appInkMuted)
                }
            }
            .padding(.top, 2)
        } else if !isLocked {
            Button("Add Description") {
                descriptionText = ""
                showingDescriptionEditor = true
            }
            .font(.footnote)
            .foregroundStyle(Color.appAccent)
            .padding(.top, 2)
        }
    }

    private var heroInfoLine: String {
        let exerciseCount = workout.sortedBlocks.reduce(0) { total, block in
            total + (block.blockType == .time
                ? block.sortedTimeSteps.filter { $0.stepType == .exercise }.count
                : block.sortedRepExercises.count)
        }
        let exercisesText = "\(exerciseCount) Exercise\(exerciseCount == 1 ? "" : "s")"
        switch workout.kind {
        case .personalized:
            let blockCount = workout.sortedBlocks.count
            return "\(blockCount) Block\(blockCount == 1 ? "" : "s") · \(exercisesText) · Personalized"
        case .byTime:
            return "\(exercisesText) · Follow Along"
        case .byRep:
            return "\(exercisesText) · By Reps"
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
        return block.blockType == .time ? "Follow Along Block" : "Rep Block"
    }

    /// Header + exercise rows all inside one `.cardStyle()` container so the block's
    /// title and its exercises read as one visually connected unit, rather than a
    /// native List section header floating above loose rows.
    private func blockCard(_ block: WorkoutBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            blockSectionHeader(block)
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
            ForEach(overviewItems(for: block)) { item in
                overviewItemRow(item)
            }
        }
        .padding(16)
        .cardStyle()
    }

    @ViewBuilder
    private func blockSectionHeader(_ block: WorkoutBlock) -> some View {
        HStack(spacing: 12) {
            if workout.kind == .personalized {
                Text(blockTitle(block))
                    .font(.headline)
                    .foregroundStyle(Color.appInk)
            } else {
                Text("Exercises")
                    .textCase(.uppercase)
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
            }

            Spacer()

            // While rearranging, the only actions available are dragging blocks and
            // adding a new one — Clone/Delete/Manage Exercises hide entirely so a stray
            // tap can't do anything else mid-reorder.
            if !isLocked && !editMode.isEditing {
                if workout.kind == .personalized {
                    Button {
                        cloneBlock(block)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appInkMuted)

                    Button {
                        blockPendingDeletion = block
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appDanger)
                }

                // A plain Button here, not NavigationLink — List auto-adds a trailing
                // disclosure chevron to any row containing a NavigationLink, even one
                // that's just a small inline element rather than the whole row. Manage
                // Exercises is already the only tap target that goes anywhere, so the
                // extra chevron was redundant.
                Button {
                    manageExercisesBlock = block
                } label: {
                    // Personalized already has two other icon-only actions (Clone,
                    // Delete) alongside this one, so a pencil keeps the row consistent;
                    // Follow Along/By Reps has only this one action, where text reads
                    // more clearly on its own.
                    if workout.kind == .personalized {
                        Image(systemName: "pencil")
                    } else {
                        Text("Manage Exercises")
                            .font(.subheadline)
                    }
                }
                .foregroundStyle(Color.appAccent)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var blockListControls: some View {
        HStack(spacing: 16) {
            Spacer()

            Menu {
                Button("Follow Along Block") { addBlock(.time) }
                Button("Rep Block") { addBlock(.rep) }
            } label: {
                Text("Add a Block")
            }
            .buttonStyle(.borderedProminent)

            if workout.sortedBlocks.count > 1 {
                Button {
                    editMode = editMode.isEditing ? .inactive : .active
                } label: {
                    Text(editMode.isEditing ? "Done" : "Rearrange Blocks")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func addBlock(_ type: WorkoutBlockType) {
        do { _ = try WorkoutEditingService.addBlock(to: workout, type: type, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cloneBlock(_ block: WorkoutBlock) {
        do { _ = try WorkoutBlockCloningService.cloneBlock(block, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func confirmDeleteBlock() {
        guard let block = blockPendingDeletion else { return }
        do { try WorkoutEditingService.deleteBlock(block, from: workout, context: context) }
        catch { errorMessage = error.localizedDescription }
        blockPendingDeletion = nil
    }

    // nil (not just a hidden drag handle) while not rearranging, so blocks genuinely
    // can't be reordered outside that mode — same optional-closure pattern used for
    // `moveBlocksAction` in WorkoutEditorView.
    private var reorderAction: ((IndexSet, Int) -> Void)? {
        if !editMode.isEditing { return nil }
        return moveBlocks
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveBlocks(in: workout, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func renameWorkout() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try WorkoutEditingService.rename(workout, to: trimmed, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var descriptionEditorSheet: some View {
        NavigationStack {
            Form {
                TextEditor(text: $descriptionText)
                    .frame(minHeight: 160)
            }
            .themedListBackground()
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingDescriptionEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveDescription() }
                }
            }
        }
    }

    private func saveDescription() {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try WorkoutEditingService.updateNotes(workout, to: trimmed.isEmpty ? nil : trimmed, context: context)
            showingDescriptionEditor = false
        } catch {
            errorMessage = error.localizedDescription
        }
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
                    detail: repExerciseDetail(for: entry)
                )
            }
        }
    }

    private func repExerciseDetail(for entry: RepBlockExercise) -> String {
        switch entry.trackingMode {
        case .repsWeight:
            return "\(entry.targetSets) sets · rest \(entry.customRestSeconds.map { "\($0)s" } ?? "default")"
        case .maxHoldTime:
            return "\(entry.targetSets) sets · max hold · \(entry.headStartSeconds)s head start"
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
