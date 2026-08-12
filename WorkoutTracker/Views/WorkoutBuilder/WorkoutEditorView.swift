import SwiftUI
import SwiftData

private struct OverviewItem: Identifiable {
    let id: UUID
    let iconName: String
    let title: String
    let detail: String
}

struct WorkoutEditorView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context

    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    private var isLocked: Bool { workout.isLocked }

    var body: some View {
        listContent
            .environment(\.editMode, $editMode)
            .themedListBackground()
            .navigationTitle(workout.name.isEmpty ? "Workout" : workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { mainToolbar }
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
    private var listContent: some View {
        List {
            nameSection
            blocksSection
        }
    }

    @ViewBuilder
    private var nameSection: some View {
        Section {
            TextField("Name", text: Binding(
                get: { workout.name },
                set: { newValue in
                    do { try WorkoutEditingService.rename(workout, to: newValue, context: context) }
                    catch { errorMessage = error.localizedDescription }
                }
            ))
            .disabled(isLocked)
            LabeledContent("Type", value: workout.displayType.rawValue.capitalized)
        }
    }

    @ViewBuilder
    private var blocksSection: some View {
        Section("Blocks") {
            if workout.sortedBlocks.isEmpty {
                Text("No blocks yet").foregroundStyle(.secondary)
            }
            blockRows
            addBlockMenu
        }
    }

    private var blockRows: some View {
        ForEach(workout.sortedBlocks) { block in
            NavigationLink {
                BlockEditorView(block: block)
            } label: {
                blockRow(block)
            }
            .swipeActions(edge: .leading) {
                cloneBlockButton(block)
            }
        }
        .onDelete(perform: deleteBlocksAction)
        .onMove(perform: moveBlocksAction)
    }

    @ViewBuilder
    private func cloneBlockButton(_ block: WorkoutBlock) -> some View {
        if !isLocked {
            Button {
                cloneBlock(block)
            } label: {
                Label("Clone Block", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }

    // Explicit optional-closure types here sidestep a real Swift inference limitation:
    // `isLocked ? nil : someFunctionReference` inline in a modifier argument position
    // fails to type-check ("ambiguous"/"failed to produce diagnostic") without one.
    private var deleteBlocksAction: ((IndexSet) -> Void)? {
        if isLocked { return nil }
        return deleteBlocks
    }

    private var moveBlocksAction: ((IndexSet, Int) -> Void)? {
        if isLocked { return nil }
        return moveBlocks
    }

    @ViewBuilder
    private var addBlockMenu: some View {
        if !isLocked {
            if workout.kind == .personalized {
                Menu {
                    Button("Time Block") { addBlock(.time) }
                    Button("Repetition Block") { addBlock(.rep) }
                } label: {
                    Label("Add Block", systemImage: "plus")
                }
            } else if workout.sortedBlocks.isEmpty {
                Button {
                    addBlock(workout.kind == .byTime ? .time : .rep)
                } label: {
                    Label("Add Block", systemImage: "plus")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                editMode = editMode.isEditing ? .inactive : .active
            } label: {
                Image(systemName: editMode.isEditing ? "checkmark" : "pencil")
            }
        }
    }

    private func blockRow(_ block: WorkoutBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(systemName: block.blockType == .time ? "timer" : "list.number")
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: block))
                    Text(block.blockType == .time ? "\(block.sortedTimeSteps.count) steps" : "\(block.sortedRepExercises.count) exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(overviewItems(for: block)) { item in
                overviewItemRow(item)
            }
        }
        .padding(.vertical, 4)
    }

    /// One row per contained exercise/rest, shown directly under its block so the whole
    /// workout's contents are visible at a glance without navigating into each block.
    private func overviewItems(for block: WorkoutBlock) -> [OverviewItem] {
        if block.blockType == .time {
            return block.sortedTimeSteps.map { step in
                OverviewItem(
                    id: step.id,
                    iconName: overviewIcon(for: step),
                    title: overviewTitle(for: step),
                    detail: "\(step.durationSeconds)s"
                )
            }
        } else {
            return block.sortedRepExercises.map { entry in
                OverviewItem(
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

    private func overviewItemRow(_ item: OverviewItem) -> some View {
        HStack {
            Image(systemName: item.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(item.title)
                .font(.subheadline)
            Spacer()
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }

    private func displayName(for block: WorkoutBlock) -> String {
        if let name = block.name, !name.isEmpty { return name }
        return block.blockType == .time ? "Time Block" : "Rep Block"
    }

    private func addBlock(_ type: WorkoutBlockType) {
        do { _ = try WorkoutEditingService.addBlock(to: workout, type: type, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let blocks = workout.sortedBlocks
        for index in offsets {
            do { try WorkoutEditingService.deleteBlock(blocks[index], from: workout, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveBlocks(in: workout, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cloneBlock(_ block: WorkoutBlock) {
        do { _ = try WorkoutBlockCloningService.cloneBlock(block, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
