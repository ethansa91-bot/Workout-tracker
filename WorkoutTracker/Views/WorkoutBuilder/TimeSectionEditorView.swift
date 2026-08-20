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
    @State private var expandedStepID: UUID?
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
            "Delete \(selectedStepIDs.count) selected step\(selectedStepIDs.count == 1 ? "" : "s")?",
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
        let count = section.sortedTimeSteps.filter { $0.stepType == .exercise }.count
        return "\(section.sectionType.pillLabel) · \(count) Exercise\(count == 1 ? "" : "s")"
    }

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Autostart", isOn: autostartBinding)
            Stepper(repeatLabel(section.repeatCount), value: repeatBinding, in: 1...20)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var autostartBinding: Binding<Bool> {
        Binding(get: { section.autostart }, set: { updateAutostart($0) })
    }

    private var repeatBinding: Binding<Int> {
        Binding(get: { section.repeatCount }, set: { updateRepeatCount($0) })
    }

    private func updateAutostart(_ autostart: Bool) {
        do { try WorkoutEditingService.updateAutostart(section, to: autostart, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func updateRepeatCount(_ count: Int) {
        do { try WorkoutEditingService.updateRepeatCount(section, to: count, context: context) }
        catch { errorMessage = error.localizedDescription }
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
                        .disabled(selectedStepIDs.isEmpty)
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
        Text("No steps yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var existingExerciseIDs: Set<UUID> {
        Set(section.sortedTimeSteps.compactMap { $0.exercise?.id })
    }

    @ViewBuilder
    private func stepRow(_ step: TimeSectionStep) -> some View {
        let isExpanded = !isEditing && expandedStepID == step.id
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                stepRowContent(step)
            } else {
                stepRowContent(step)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLocked else { return }
                        withAnimation {
                            expandedStepID = (expandedStepID == step.id) ? nil : step.id
                        }
                    }
            }
            if isExpanded {
                TimeStepInlineEditor(step: step, context: context, onAddRest: { addRest(after: step) })
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .listRowBackground(isExpanded ? Color.appHighlightGray : nil)
    }

    private func stepRowContent(_ step: TimeSectionStep) -> some View {
        HStack(spacing: 12) {
            switch step.stepType {
            case .exercise:
                IconBadge(systemName: step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional", tint: step.effectiveColor?.color ?? .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.exercise?.displayName ?? "Exercise")
                    Text("\(step.durationSeconds)s").font(.caption).foregroundStyle(Color.appRust)
                }
            case .rest:
                IconBadge(systemName: "pause.circle", tint: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest")
                    Text("\(step.durationSeconds)s").font(.caption).foregroundStyle(Color.appRust)
                }
            case .getReady:
                IconBadge(systemName: "hourglass", tint: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Ready")
                    Text("\(step.durationSeconds)s").font(.caption).foregroundStyle(Color.appRust)
                }
            }
            Spacer()
            if !isEditing {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expandedStepID == step.id ? 90 : 0))
            }
        }
        .padding(.vertical, 2)
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

/// Inline accordion body shown beneath an expanded `TimeSectionStep` row — every field
/// saves immediately on change, rather than requiring an explicit Save button.
private struct TimeStepInlineEditor: View {
    @Bindable var step: TimeSectionStep
    let context: ModelContext
    let onAddRest: () -> Void

    @State private var showingExercisePicker = false

    private var durationRange: ClosedRange<Int> {
        step.stepType == .getReady ? 0...300 : 5...600
    }

    private var hasRestAfter: Bool {
        guard let steps = step.section?.sortedTimeSteps,
              let index = steps.firstIndex(where: { $0.id == step.id }),
              index + 1 < steps.count
        else { return false }
        return steps[index + 1].stepType == .rest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("Duration: \(step.durationSeconds)s", value: Binding(
                get: { step.durationSeconds },
                set: { step.durationSeconds = $0; save() }
            ), in: durationRange, step: 5)

            if step.stepType == .exercise {
                Button("Add Rest", action: onAddRest)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(hasRestAfter)

                colorPicker
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 4)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                step.exercise = exercise
                save()
            }
        }
    }

    /// Every exercise step can have its own color, independent of every other step in
    /// the section — this is what `SessionScrubStripView` highlights the step's chip
    /// with while it's active. Tapping the already-selected color clears it back to
    /// the default accent.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)
            PaletteColorPicker(selection: Binding(
                get: { step.color },
                set: { step.color = $0; save() }
            ))
        }
    }

    private func save() {
        step.markDirty()
        try? context.save()
    }
}
