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
    @State private var showingEditSheet = false
    @State private var nameText = ""
    @State private var descriptionText = ""

    private var isLocked: Bool { section.isLocked }
    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        VStack(spacing: 0) {
            if !isLocked {
                heroCard
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
        .alert(
            "Delete \(selectedEntryIDs.count) selected exercise\(selectedEntryIDs.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingEditSheet) {
            editSheet
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

    /// Same hero-card treatment as `SessionRecapView`'s workout header — name + a
    /// single pencil opening one sheet that edits both name and description together.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(section.name?.isEmpty == false ? section.name! : section.sectionType.fallbackSectionName)
                    .font(.appSerif(.title2))
                    .foregroundStyle(Color.appInk)
                Button {
                    nameText = section.name ?? ""
                    descriptionText = section.sectionDescription ?? ""
                    showingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appInkMuted)
            }
            if let description = section.sectionDescription, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
            }

            Text(heroInfoLine)
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var heroInfoLine: String {
        let count = section.sortedQuickExercises.count
        return "\(section.sectionType.pillLabel) · \(count) Exercise\(count == 1 ? "" : "s")"
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $nameText)
                }
                Section("Description") {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 160)
                }
            }
            .themedListBackground()
            .navigationTitle("Edit Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdits() }
                }
            }
        }
    }

    @ViewBuilder
    private var settingsBar: some View {
        switch section.sectionType {
        case .emom:
            VStack(alignment: .leading, spacing: 0) {
                Stepper("Rounds: \(section.emomRoundCount) (\(section.emomRoundCount) min)", value: emomRoundsBinding, in: 1...60)
                Toggle("Autostart", isOn: autostartBinding)
                Stepper(repeatLabel(section.repeatCount), value: repeatBinding, in: 1...20)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        case .amrap:
            VStack(alignment: .leading, spacing: 0) {
                Stepper("Duration: \(section.amrapDurationSeconds / 60) min", value: amrapMinutesBinding, in: 1...60)
                Toggle("Autostart", isOn: autostartBinding)
                Stepper(repeatLabel(section.repeatCount), value: repeatBinding, in: 1...20)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        case .time, .rep:
            EmptyView()
        }
    }

    private var emomRoundsBinding: Binding<Int> {
        Binding(get: { section.emomRoundCount }, set: { updateEmomRounds($0) })
    }

    private var repeatBinding: Binding<Int> {
        Binding(get: { section.repeatCount }, set: { updateRepeatCount($0) })
    }

    private var amrapMinutesBinding: Binding<Int> {
        Binding(get: { section.amrapDurationSeconds / 60 }, set: { updateAmrapDuration($0 * 60) })
    }

    private var autostartBinding: Binding<Bool> {
        Binding(get: { section.autostart }, set: { updateAutostart($0) })
    }

    /// Save (left) / Add Exercises (centered) / Edit (right) when browsing; Delete
    /// (centered) when in multi-select mode — all in the same glass style as
    /// `SessionRecapView`'s "New Section" row, grouped in one `GlassEffectContainer` so
    /// nearby glass buttons render as a single coherent pass.
    @ViewBuilder
    private var headerBar: some View {
        GlassEffectContainer {
            ZStack {
                if !isEditing {
                    HStack {
                        Button {
                            finishEditing()
                        } label: {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.glass)
                        Spacer()
                    }
                }

                HStack {
                    Spacer()
                    if isEditing {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Text("Delete").foregroundStyle(Color.appDanger)
                        }
                        .buttonStyle(.glass)
                        .disabled(selectedEntryIDs.isEmpty)
                    } else {
                        Button {
                            showingAddExercises = true
                        } label: {
                            Text("Add Exercises").foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.glass)
                    }
                    Spacer()
                }

                HStack {
                    Spacer()
                    Button {
                        editMode = isEditing ? .inactive : .active
                    } label: {
                        Image(systemName: isEditing ? "xmark" : "pencil")
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding()
    }

    private var emptyState: some View {
        Text("No exercises yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var existingExerciseIDs: Set<UUID> {
        Set(section.sortedQuickExercises.compactMap { $0.exercise?.id })
    }

    private func entryRow(_ entry: SectionExerciseEntry) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
            Text(entry.exercise?.displayName ?? "Exercise")
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

    private func updateAutostart(_ autostart: Bool) {
        do { try WorkoutEditingService.updateAutostart(section, to: autostart, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func updateRepeatCount(_ count: Int) {
        do { try WorkoutEditingService.updateRepeatCount(section, to: count, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func finishEditing() {
        if onSaveNavigatesToRecap {
            showingRecap = true
        } else {
            dismiss()
        }
    }

    private func saveEdits() {
        let trimmedName = nameText.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedName.isEmpty {
                try WorkoutEditingService.rename(section, to: trimmedName, context: context)
            }
            try WorkoutEditingService.updateDescription(section, to: trimmedDescription.isEmpty ? nil : trimmedDescription, context: context)
            showingEditSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
