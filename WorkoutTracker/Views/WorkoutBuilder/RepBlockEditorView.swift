import SwiftUI
import SwiftData

struct RepBlockEditorView: View {
    @Bindable var block: WorkoutBlock
    @Environment(\.modelContext) private var context

    @State private var editMode: EditMode = .inactive
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showingAddExercises = false
    @State private var editingEntry: RepBlockExercise?
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
                if block.sortedRepExercises.isEmpty {
                    emptyState
                } else {
                    List(selection: $selectedEntryIDs) {
                        ForEach(block.sortedRepExercises) { entry in
                            entryRow(entry)
                        }
                        .onMove(perform: moveEntriesAction)
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
        .sheet(item: $editingEntry) { entry in
            RepExerciseFormView(block: block, editingEntry: entry)
        }
        .confirmationDialog(
            "Delete \(selectedEntryIDs.count) selected exercise\(selectedEntryIDs.count == 1 ? "" : "s")?",
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
                    .disabled(selectedEntryIDs.isEmpty)
            }
            .padding()
        } else {
            HStack {
                Button("Add Exercises") { showingAddExercises = true }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Save") { showingRecap = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var emptyState: some View {
        Text("No exercises yet")
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
        Set(block.sortedRepExercises.compactMap { $0.exercise?.id })
    }

    @ViewBuilder
    private func entryRow(_ entry: RepBlockExercise) -> some View {
        if isEditing {
            entryRowContent(entry)
        } else {
            entryRowContent(entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isLocked { editingEntry = entry }
                }
        }
    }

    private func entryRowContent(_ entry: RepBlockExercise) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise?.name ?? "Exercise")
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for entry: RepBlockExercise) -> String {
        switch entry.trackingMode {
        case .repsWeight:
            return "\(entry.targetSets) sets · rest \(entry.customRestSeconds.map { "\($0)s" } ?? "default")"
        case .maxHoldTime:
            return "\(entry.targetSets) sets · max hold · \(entry.headStartSeconds)s head start"
        }
    }

    private var moveEntriesAction: ((IndexSet, Int) -> Void)? {
        if isLocked { return nil }
        return moveEntries
    }

    private var isContiguousSelection: Bool {
        guard !selectedEntryIDs.isEmpty else { return false }
        let entries = block.sortedRepExercises
        let indices = entries.indices.filter { selectedEntryIDs.contains(entries[$0].id) }
        guard let first = indices.first, let last = indices.last else { return false }
        return indices.count == (last - first + 1)
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveRepExercises(in: block, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func addExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            do {
                try WorkoutEditingService.addRepExercise(to: block, exercise: exercise, targetSets: 3, customRestSeconds: nil, context: context)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
    }

    private func cloneSelection() {
        let entries = block.sortedRepExercises
        let indices = entries.indices.filter { selectedEntryIDs.contains(entries[$0].id) }
        guard let first = indices.first, let last = indices.last else { return }
        do {
            try WorkoutBlockCloningService.cloneRepExercises(in: block, range: first..<(last + 1), context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelection() {
        let entries = block.sortedRepExercises
        for entry in entries where selectedEntryIDs.contains(entry.id) {
            do { try WorkoutEditingService.deleteRepExercise(entry, from: block, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
        selectedEntryIDs.removeAll()
    }
}
