import SwiftUI
import SwiftData

struct TimeSectionEditorView: View {
    @Bindable var section: WorkoutSection
    var onSaveNavigatesToRecap: Bool = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var selectedStepIDs: Set<UUID> = []
    @State private var showingAddExercises = false
    @State private var editingStep: TimeSectionStep?
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var showingRecap = false
    @State private var nameField: String = ""

    private var isLocked: Bool { section.isLocked }
    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        VStack(spacing: 0) {
            if !isLocked {
                nameBar
                headerBar
                Divider()
            }
            Group {
                if section.sortedTimeSteps.isEmpty {
                    emptyState
                } else {
                    List(selection: $selectedStepIDs) {
                        ForEach(section.sortedTimeSteps) { step in
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
        .onAppear { nameField = section.name ?? "" }
        .navigationDestination(isPresented: $showingRecap) {
            if let workout = section.workout {
                SessionRecapView(workout: workout)
            }
        }
        .sheet(isPresented: $showingAddExercises) {
            MultiExercisePickerView(existingExerciseIDs: existingExerciseIDs) { exercises in
                addExercises(exercises)
            }
        }
        .sheet(item: $editingStep) { step in
            TimeStepFormView(section: section, stepType: step.stepType, editingStep: step)
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

    private var nameBar: some View {
        TextField(section.sectionType == .time ? "Follow Along Section" : "Section Name", text: $nameField)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.top, 12)
            .submitLabel(.done)
            .onSubmit { renameSection() }
            .onDisappear { renameSection() }
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
                    renameSection()
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
        Set(section.sortedTimeSteps.compactMap { $0.exercise?.id })
    }

    @ViewBuilder
    private func stepRow(_ step: TimeSectionStep) -> some View {
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

    private func stepRowContent(_ step: TimeSectionStep) -> some View {
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

    private func addRestButton(after step: TimeSectionStep) -> some View {
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

    private func hasRestAfter(_ step: TimeSectionStep) -> Bool {
        let steps = section.sortedTimeSteps
        guard let index = steps.firstIndex(where: { $0.id == step.id }), index + 1 < steps.count else { return false }
        return steps[index + 1].stepType == .rest
    }

    private var moveStepsAction: ((IndexSet, Int) -> Void)? {
        if isLocked { return nil }
        return moveSteps
    }

    private var isContiguousSelection: Bool {
        guard !selectedStepIDs.isEmpty else { return false }
        let steps = section.sortedTimeSteps
        let indices = steps.indices.filter { selectedStepIDs.contains(steps[$0].id) }
        guard let first = indices.first, let last = indices.last else { return false }
        return indices.count == (last - first + 1)
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveTimeSteps(in: section, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func addExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            do {
                try WorkoutEditingService.addTimeStep(to: section, stepType: .exercise, exercise: exercise, durationSeconds: 30, context: context)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
    }

    private func addRest(after step: TimeSectionStep) {
        do { try WorkoutEditingService.addRestStep(after: step, durationSeconds: 30, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cloneSelection() {
        let steps = section.sortedTimeSteps
        let indices = steps.indices.filter { selectedStepIDs.contains(steps[$0].id) }
        guard let first = indices.first, let last = indices.last else { return }
        do {
            try WorkoutSectionCloningService.cloneTimeSteps(in: section, range: first..<(last + 1), context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelection() {
        let steps = section.sortedTimeSteps
        for step in steps where selectedStepIDs.contains(step.id) {
            do { try WorkoutEditingService.deleteTimeStep(step, from: section, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
        selectedStepIDs.removeAll()
    }

    private func renameSection() {
        let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? nil : trimmed
        guard newName != section.name else { return }
        do { try WorkoutEditingService.rename(section, to: newName, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
