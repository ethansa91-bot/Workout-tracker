import SwiftUI
import SwiftData

struct TimeBlockEditorView: View {
    @Bindable var block: WorkoutBlock
    var onSaveNavigatesToRecap: Bool = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var selectedStepIDs: Set<UUID> = []
    @State private var showingAddExercises = false
    @State private var editingStep: TimeBlockStep?
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var showingRecap = false

    private var isLocked: Bool { block.workout?.isLocked ?? true }
    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        VStack(spacing: 0) {
            if !isLocked {
                headerBar
                Divider()
            }
            Group {
                if block.sortedTimeSteps.isEmpty {
                    emptyState
                } else {
                    List(selection: $selectedStepIDs) {
                        ForEach(block.sortedTimeSteps) { step in
                            stepRow(step)
                                .selectionDisabled(step.stepType == .getReady)
                                .moveDisabled(step.stepType == .getReady)
                        }
                        .onMove(perform: moveStepsAction)
                    }
                    .environment(\.editMode, $editMode)
                    .themedListBackground()
                }
            }
        }
        .background(Color.appBackground)
        .toolbar { mainToolbar }
        .navigationDestination(isPresented: $showingRecap) {
            if let workout = block.workout {
                SessionRecapView(workout: workout)
            }
        }
        .sheet(isPresented: $showingAddExercises) {
            MultiExercisePickerView(existingExerciseIDs: existingExerciseIDs) { exercises in
                addExercises(exercises)
            }
        }
        .sheet(item: $editingStep) { step in
            TimeStepFormView(block: block, stepType: step.stepType, editingStep: step)
        }
        .confirmationDialog(
            "Delete \(selectedStepIDs.count) selected step\(selectedStepIDs.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
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
    private var headerBar: some View {
        if isEditing {
            HStack {
                Button("Clone") { cloneSelection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isContiguousSelection)
                Spacer()
                Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appDanger)
                    .disabled(selectedStepIDs.isEmpty)
            }
            .padding()
        } else {
            HStack {
                Button("Add Exercises") { showingAddExercises = true }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Save") {
                    if onSaveNavigatesToRecap {
                        showingRecap = true
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var emptyState: some View {
        Text("No steps yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        if !isLocked {
            ToolbarItem(placement: .topBarTrailing) {
                // A plain custom Button that mutates our own `@State editMode`
                // directly — the system `EditButton()` was found (via live device
                // testing) to toggle its own label without ever writing through to
                // our `.environment(\.editMode, $editMode)` binding, leaving the
                // List/header permanently stuck in the non-editing state.
                Button {
                    editMode = isEditing ? .inactive : .active
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                }
            }
        }
    }

    private var existingExerciseIDs: Set<UUID> {
        Set(block.sortedTimeSteps.compactMap { $0.exercise?.id })
    }

    @ViewBuilder
    private func stepRow(_ step: TimeBlockStep) -> some View {
        if isEditing {
            stepRowContent(step)
        } else {
            stepRowContent(step)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isLocked { editingStep = step }
                }
        }
    }

    private func stepRowContent(_ step: TimeBlockStep) -> some View {
        HStack(spacing: 12) {
            switch step.stepType {
            case .exercise:
                IconBadge(systemName: step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.exercise?.name ?? "Exercise")
                    Text("\(step.durationSeconds)s").font(.caption).foregroundStyle(.secondary)
                }
            case .rest:
                IconBadge(systemName: "pause.circle", tint: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest")
                    Text("\(step.durationSeconds)s").font(.caption).foregroundStyle(.secondary)
                }
            case .getReady:
                IconBadge(systemName: "hourglass", tint: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Ready")
                    Text("\(step.durationSeconds)s").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if step.stepType == .exercise && !isEditing && !isLocked {
                addRestButton(after: step)
            }
        }
        .padding(.vertical, 2)
    }

    private func addRestButton(after step: TimeBlockStep) -> some View {
        Button {
            addRest(after: step)
        } label: {
            Label("Add Rest", systemImage: "plus.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasRestAfter(step) ? Color.secondary.opacity(0.4) : Color.accentColor)
        .disabled(hasRestAfter(step))
    }

    private func hasRestAfter(_ step: TimeBlockStep) -> Bool {
        let steps = block.sortedTimeSteps
        guard let index = steps.firstIndex(where: { $0.id == step.id }), index + 1 < steps.count else { return false }
        return steps[index + 1].stepType == .rest
    }

    private var moveStepsAction: ((IndexSet, Int) -> Void)? {
        if isLocked { return nil }
        return moveSteps
    }

    private var isContiguousSelection: Bool {
        guard !selectedStepIDs.isEmpty else { return false }
        let steps = block.sortedTimeSteps
        let indices = steps.indices.filter { selectedStepIDs.contains(steps[$0].id) }
        guard let first = indices.first, let last = indices.last else { return false }
        return indices.count == (last - first + 1)
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveTimeSteps(in: block, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func addExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            do {
                try WorkoutEditingService.addTimeStep(to: block, stepType: .exercise, exercise: exercise, durationSeconds: 30, context: context)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
    }

    private func addRest(after step: TimeBlockStep) {
        do { try WorkoutEditingService.addRestStep(after: step, durationSeconds: 30, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cloneSelection() {
        let steps = block.sortedTimeSteps
        let indices = steps.indices.filter { selectedStepIDs.contains(steps[$0].id) }
        guard let first = indices.first, let last = indices.last else { return }
        do {
            try WorkoutBlockCloningService.cloneTimeSteps(in: block, range: first..<(last + 1), context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelection() {
        let steps = block.sortedTimeSteps
        for step in steps where selectedStepIDs.contains(step.id) {
            do { try WorkoutEditingService.deleteTimeStep(step, from: block, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
        selectedStepIDs.removeAll()
    }
}
