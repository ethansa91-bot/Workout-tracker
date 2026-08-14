import SwiftUI
import SwiftData

struct RepSectionEditorView: View {
    @Bindable var section: WorkoutSection
    var onSaveNavigatesToRecap: Bool = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showingAddExercises = false
    @State private var expandedEntryID: UUID?
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
                headerBar
                Divider()
            }
            Group {
                if section.sortedRepExercises.isEmpty {
                    emptyState
                } else {
                    List(selection: $selectedEntryIDs) {
                        ForEach(section.sortedRepExercises) { entry in
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
        .confirmationDialog(
            "Delete \(selectedEntryIDs.count) selected exercise\(selectedEntryIDs.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
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
        let count = section.sortedRepExercises.count
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

    /// Save (left) / Add Exercises (centered) / Edit (right) when browsing; Clone +
    /// Delete (centered) when in multi-select mode — all in the same glass style as
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
                        Button {
                            cloneSelection()
                        } label: {
                            Text("Clone").foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.glass)
                        .disabled(!isContiguousSelection)

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
        Set(section.sortedRepExercises.compactMap { $0.exercise?.id })
    }

    @ViewBuilder
    private func entryRow(_ entry: RepSectionExercise) -> some View {
        let isExpanded = !isEditing && expandedEntryID == entry.id
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                entryRowContent(entry)
            } else {
                entryRowContent(entry)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLocked else { return }
                        withAnimation {
                            expandedEntryID = (expandedEntryID == entry.id) ? nil : entry.id
                        }
                    }
            }
            if isExpanded {
                RepEntryInlineEditor(entry: entry, context: context)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, isExpanded ? 8 : 0)
        .background(
            isExpanded ? Color.appAccent.opacity(0.07) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func entryRowContent(_ entry: RepSectionExercise) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise?.displayName ?? "Exercise")
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(Color.appRust)
            }
            if !isEditing {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expandedEntryID == entry.id ? 90 : 0))
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for entry: RepSectionExercise) -> String {
        switch entry.trackingMode {
        case .repsWeight:
            let rest = entry.customRestSeconds ?? AppSettings.defaultRestSeconds
            return "\(entry.targetSets) sets · rest \(rest)s"
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
        let entries = section.sortedRepExercises
        let indices = entries.indices.filter { selectedEntryIDs.contains(entries[$0].id) }
        guard let first = indices.first, let last = indices.last else { return false }
        return indices.count == (last - first + 1)
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveRepExercises(in: section, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func addExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            do {
                try WorkoutEditingService.addRepExercise(to: section, exercise: exercise, targetSets: 3, customRestSeconds: nil, context: context)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
    }

    private func cloneSelection() {
        let entries = section.sortedRepExercises
        let indices = entries.indices.filter { selectedEntryIDs.contains(entries[$0].id) }
        guard let first = indices.first, let last = indices.last else { return }
        do {
            try WorkoutSectionCloningService.cloneRepExercises(in: section, range: first..<(last + 1), context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelection() {
        let entries = section.sortedRepExercises
        for entry in entries where selectedEntryIDs.contains(entry.id) {
            do { try WorkoutEditingService.deleteRepExercise(entry, from: section, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
        selectedEntryIDs.removeAll()
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

/// Inline accordion body shown beneath an expanded `RepSectionExercise` row — every
/// field saves immediately on change, rather than requiring an explicit Save button.
private struct RepEntryInlineEditor: View {
    @Bindable var entry: RepSectionExercise
    let context: ModelContext

    @State private var showingExercisePicker = false

    private var restBinding: Binding<Int> {
        Binding(
            get: { entry.customRestSeconds ?? AppSettings.defaultRestSeconds },
            set: { newValue in
                entry.customRestSeconds = newValue == AppSettings.defaultRestSeconds ? nil : newValue
                save()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Change Exercise") {
                showingExercisePicker = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .center)

            Stepper("Sets: \(entry.targetSets)", value: Binding(
                get: { entry.targetSets },
                set: { entry.targetSets = $0; save() }
            ), in: 1...20)

            Stepper("Rest: \(restBinding.wrappedValue)s", value: restBinding, in: 0...600, step: 15)

            Picker("Track by", selection: Binding(
                get: { entry.trackingMode },
                set: { entry.trackingMode = $0; save() }
            )) {
                Text("Reps & Weight").tag(RepExerciseTrackingMode.repsWeight)
                Text("Max Hold Time").tag(RepExerciseTrackingMode.maxHoldTime)
            }
            .pickerStyle(.segmented)

            if entry.trackingMode == .maxHoldTime {
                Stepper("Head start: \(entry.headStartSeconds)s", value: Binding(
                    get: { entry.headStartSeconds },
                    set: { entry.headStartSeconds = $0; save() }
                ), in: 0...30)
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 4)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                entry.exercise = exercise
                save()
            }
        }
    }

    private func save() {
        entry.markDirty()
        try? context.save()
    }
}
