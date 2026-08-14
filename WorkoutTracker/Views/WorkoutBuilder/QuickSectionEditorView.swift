import SwiftUI
import SwiftData

/// Shared editor for EMOM and AMRAP sections — both are just a short list of
/// exercises (all shown at once during the session, no per-exercise settings) plus a
/// single section-level timing setting (EMOM: round count; AMRAP: total duration).
struct QuickSectionEditorView: View {
    @Bindable var section: WorkoutSection
    var onSaveNavigatesToRecap: Bool = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showingAddExercises = false
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
                settingsBar
                headerBar
                Divider()
            }
            Group {
                if section.sortedQuickExercises.isEmpty {
                    emptyState
                } else {
                    List(selection: $selectedEntryIDs) {
                        ForEach(section.sortedQuickExercises) { entry in
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

    private var nameBar: some View {
        TextField(section.sectionType.fallbackSectionName, text: $nameField)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.top, 12)
            .submitLabel(.done)
            .onSubmit { renameSection() }
            .onDisappear { renameSection() }
    }

    @ViewBuilder
    private var settingsBar: some View {
        switch section.sectionType {
        case .emom:
            Stepper("Rounds: \(section.emomRoundCount) (\(section.emomRoundCount) min)", value: emomRoundsBinding, in: 1...60)
                .padding(.horizontal)
                .padding(.top, 8)
        case .amrap:
            Stepper("Duration: \(section.amrapDurationSeconds / 60) min", value: amrapMinutesBinding, in: 1...60)
                .padding(.horizontal)
                .padding(.top, 8)
        case .time, .rep:
            EmptyView()
        }
    }

    private var emomRoundsBinding: Binding<Int> {
        Binding(get: { section.emomRoundCount }, set: { updateEmomRounds($0) })
    }

    private var amrapMinutesBinding: Binding<Int> {
        Binding(get: { section.amrapDurationSeconds / 60 }, set: { updateAmrapDuration($0 * 60) })
    }

    @ViewBuilder
    private var headerBar: some View {
        if isEditing {
            HStack {
                Spacer()
                Button("Delete", role: .destructive) { showingDeleteConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appDanger)
                    .disabled(selectedEntryIDs.isEmpty)
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
        Text("No exercises yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        if !isLocked {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editMode = isEditing ? .inactive : .active
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                }
            }
        }
    }

    private var existingExerciseIDs: Set<UUID> {
        Set(section.sortedQuickExercises.compactMap { $0.exercise?.id })
    }

    private func entryRow(_ entry: SectionExerciseEntry) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
            Text(entry.exercise?.name ?? "Exercise")
        }
        .padding(.vertical, 2)
    }

    private var moveEntriesAction: ((IndexSet, Int) -> Void)? {
        if isLocked { return nil }
        return moveEntries
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveQuickExercises(in: section, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func addExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            do {
                try WorkoutEditingService.addQuickExercise(to: section, exercise: exercise, context: context)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
    }

    private func deleteSelection() {
        let entries = section.sortedQuickExercises
        for entry in entries where selectedEntryIDs.contains(entry.id) {
            do { try WorkoutEditingService.deleteQuickExercise(entry, from: section, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
        selectedEntryIDs.removeAll()
    }

    private func updateEmomRounds(_ count: Int) {
        do { try WorkoutEditingService.updateEmomRoundCount(section, to: count, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func updateAmrapDuration(_ seconds: Int) {
        do { try WorkoutEditingService.updateAmrapDuration(section, to: seconds, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func renameSection() {
        let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? nil : trimmed
        guard newName != section.name else { return }
        do { try WorkoutEditingService.rename(section, to: newName, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
