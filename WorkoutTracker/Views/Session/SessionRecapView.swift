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
    @State private var sectionPendingDeletion: WorkoutSection?
    @State private var manageExercisesSection: WorkoutSection?
    @State private var showingDescriptionEditor = false
    @State private var descriptionText = ""
    @State private var sectionPendingSaveAsTemplate: WorkoutSection?
    @State private var templateNameText = ""
    @State private var showingImportTemplateSheet = false
    @State private var showingNewSectionSheet = false

    private var activeSoundProfile: TimerSoundProfile {
        sessionSoundProfile ?? AppSettings.timerSoundProfile
    }

    private var isLocked: Bool { workout.isLocked }
    private var pausedSession: WorkoutSession? {
        workout.sessions.first { $0.status == .paused }
    }
    /// Every section must contain at least one exercise — a workout with even a single
    /// empty section isn't ready to start, not just a workout with zero sections.
    private var allSectionsReady: Bool {
        !workout.sortedSections.isEmpty && workout.sortedSections.allSatisfy { section in
            switch section.sectionType {
            case .time: return section.sortedTimeSteps.contains { $0.stepType == .exercise }
            case .rep: return !section.sortedRepExercises.isEmpty
            case .emom, .amrap: return !section.sortedQuickExercises.isEmpty
            }
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
                    sectionListControls
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(workout.sortedSections) { section in
                    sectionCard(section)
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: reorderAction)
            }

            if !allSectionsReady {
                Text("Every section needs at least one exercise before this workout can be started.")
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
        .navigationDestination(item: $manageExercisesSection) { section in
            SectionEditorView(section: section)
        }
        .confirmationDialog(
            "Starting a new session will mark your paused session as unfinished — it can't be resumed afterward. Continue?",
            isPresented: $showingSupersedeConfirm,
            titleVisibility: .visible
        ) {
            Button("Start New", role: .destructive) { startNewSession() }
        }
        .alert(
            "Delete \"\(sectionPendingDeletion.map { sectionTitle($0) } ?? "")\"? Its exercises will be removed too.",
            isPresented: Binding(
                get: { sectionPendingDeletion != nil },
                set: { if !$0 { sectionPendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { confirmDeleteSection() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Rename Workout", isPresented: $showingRenamePrompt) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameWorkout() }
        }
        .alert("Save as Template", isPresented: Binding(
            get: { sectionPendingSaveAsTemplate != nil },
            set: { if !$0 { sectionPendingSaveAsTemplate = nil } }
        )) {
            TextField("Template name", text: $templateNameText)
            Button("Cancel", role: .cancel) { sectionPendingSaveAsTemplate = nil }
            Button("Save") { confirmSaveAsTemplate() }
        } message: {
            Text("A copy of this section's exercises will be saved to Section Templates.")
        }
        .sheet(isPresented: $showingDescriptionEditor) {
            descriptionEditorSheet
        }
        .sheet(isPresented: $showingImportTemplateSheet) {
            TemplatePickerSheet { template in
                importTemplate(template)
            }
        }
        .sheet(isPresented: $showingNewSectionSheet) {
            NewSectionTemplateSheet(title: "New Section", onCreate: createSection)
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
        } else if allSectionsReady {
            VStack(spacing: 8) {
                soundProfilePicker
                Button {
                    startNewSession()
                } label: {
                    Text("Start Workout")
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.appAccent.opacity(0.25))
            }
            .padding()
            .background(.thickMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.appHairline).frame(height: 1)
            }
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
        let exerciseCount = workout.sortedSections.reduce(0) { total, section in
            switch section.sectionType {
            case .time: return total + section.sortedTimeSteps.filter { $0.stepType == .exercise }.count
            case .rep: return total + section.sortedRepExercises.count
            case .emom, .amrap: return total + section.sortedQuickExercises.count
            }
        }
        let exercisesText = "\(exerciseCount) Exercise\(exerciseCount == 1 ? "" : "s")"
        switch workout.kind {
        case .personalized:
            let sectionCount = workout.sortedSections.count
            return "\(sectionCount) Section\(sectionCount == 1 ? "" : "s") · \(exercisesText) · Personalized"
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

    private func sectionTitle(_ section: WorkoutSection) -> String {
        if let name = section.name, !name.isEmpty { return name }
        return section.sectionType.fallbackSectionName
    }

    private func quickSectionSubtitle(_ section: WorkoutSection) -> String? {
        switch section.sectionType {
        case .emom: return "\(section.emomRoundCount) rounds · 1 min each"
        case .amrap: return "\(section.amrapDurationSeconds / 60) min AMRAP"
        case .time, .rep: return nil
        }
    }

    /// Header + exercise rows all inside one `.cardStyle()` container so the section's
    /// title and its exercises read as one visually connected unit, rather than a
    /// native List section header floating above loose rows.
    private func sectionCard(_ section: WorkoutSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(section)
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
            ForEach(overviewItems(for: section)) { item in
                overviewItemRow(item)
            }
        }
        .padding(16)
        .cardStyle()
    }

    @ViewBuilder
    private func sectionHeader(_ section: WorkoutSection) -> some View {
        HStack(spacing: 12) {
            if workout.kind == .personalized {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle(section))
                        .font(.headline)
                        .foregroundStyle(Color.appInk)
                    if let subtitle = quickSectionSubtitle(section) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.appInkMuted)
                    }
                }
            } else {
                Text("Exercises")
                    .textCase(.uppercase)
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
            }

            Spacer()

            // While rearranging, the only actions available are dragging sections and
            // adding a new one — Clone/Delete/Manage Exercises hide entirely so a stray
            // tap can't do anything else mid-reorder.
            if !isLocked && !editMode.isEditing {
                if workout.kind == .personalized {
                    Button {
                        cloneSection(section)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appInkMuted)

                    Button {
                        saveAsTemplate(section)
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appInkMuted)

                    Button {
                        sectionPendingDeletion = section
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
                    manageExercisesSection = section
                } label: {
                    // Personalized already has other icon-only actions (Clone, Save as
                    // Template, Delete) alongside this one, so a pencil keeps the row
                    // consistent; Follow Along/By Reps has only this one action, where
                    // text reads more clearly on its own.
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
    private var sectionListControls: some View {
        // Grouped in a GlassEffectContainer so the two nearby glass buttons render as
        // one coherent glass pass instead of each casting its own overlapping
        // shadow/highlight — two ungrouped glass shapes this close together produced a
        // visible smudge behind them.
        GlassEffectContainer {
            ZStack {
                HStack {
                    Spacer()
                    Menu {
                        Button("Create New Section") { showingNewSectionSheet = true }
                        Button("Import Template…") { showingImportTemplateSheet = true }
                    } label: {
                        Text("New Section")
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.glass)
                    Spacer()
                }

                if workout.sortedSections.count > 1 {
                    HStack {
                        Spacer()
                        Button {
                            editMode = editMode.isEditing ? .inactive : .active
                        } label: {
                            Image(systemName: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down")
                                .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func createSection(name: String, description: String?, type: WorkoutSectionType) {
        do {
            let section = try WorkoutEditingService.addSection(to: workout, type: type, name: name, description: description, context: context)
            manageExercisesSection = section
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cloneSection(_ section: WorkoutSection) {
        do { _ = try WorkoutSectionCloningService.cloneSection(section, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func saveAsTemplate(_ section: WorkoutSection) {
        templateNameText = sectionTitle(section)
        sectionPendingSaveAsTemplate = section
    }

    private func confirmSaveAsTemplate() {
        guard let section = sectionPendingSaveAsTemplate else { return }
        let trimmed = templateNameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do { _ = try WorkoutSectionCloningService.saveAsTemplate(section, name: trimmed, context: context) }
        catch { errorMessage = error.localizedDescription }
        sectionPendingSaveAsTemplate = nil
    }

    private func importTemplate(_ template: WorkoutSection) {
        do { _ = try WorkoutSectionCloningService.importTemplate(template, into: workout, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func confirmDeleteSection() {
        guard let section = sectionPendingDeletion else { return }
        do { try WorkoutEditingService.deleteSection(section, from: workout, context: context) }
        catch { errorMessage = error.localizedDescription }
        sectionPendingDeletion = nil
    }

    // nil (not just a hidden drag handle) while not rearranging, so sections genuinely
    // can't be reordered outside that mode — same optional-closure pattern used for
    // `moveSectionsAction` in WorkoutEditorView.
    private var reorderAction: ((IndexSet, Int) -> Void)? {
        if !editMode.isEditing { return nil }
        return moveSections
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveSections(in: workout, from: source, to: destination, context: context) }
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

    private func overviewItems(for section: WorkoutSection) -> [SessionOverviewItem] {
        switch section.sectionType {
        case .time:
            return section.sortedTimeSteps.map { step in
                SessionOverviewItem(
                    id: step.id,
                    iconName: overviewIcon(for: step),
                    title: overviewTitle(for: step),
                    detail: "\(step.durationSeconds)s"
                )
            }
        case .rep:
            return section.sortedRepExercises.map { entry in
                SessionOverviewItem(
                    id: entry.id,
                    iconName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional",
                    title: entry.exercise?.displayName ?? "Exercise",
                    detail: repExerciseDetail(for: entry)
                )
            }
        case .emom, .amrap:
            return section.sortedQuickExercises.map { entry in
                SessionOverviewItem(
                    id: entry.id,
                    iconName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional",
                    title: entry.exercise?.displayName ?? "Exercise",
                    detail: ""
                )
            }
        }
    }

    private func repExerciseDetail(for entry: RepSectionExercise) -> String {
        switch entry.trackingMode {
        case .repsWeight:
            return "\(entry.targetSets) sets · rest \(entry.customRestSeconds.map { "\($0)s" } ?? "default")"
        case .maxHoldTime:
            return "\(entry.targetSets) sets · max hold · \(entry.headStartSeconds)s head start"
        }
    }

    private func overviewIcon(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional"
        case .rest: return "pause.circle"
        case .getReady: return "hourglass"
        }
    }

    private func overviewTitle(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
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

/// Minimal list-of-templates picker presented as a sheet from "Import Template…".
private struct TemplatePickerSheet: View {
    let onSelect: (WorkoutSection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSection.name) private var allSections: [WorkoutSection]

    private var templates: [WorkoutSection] {
        allSections.filter { $0.workout == nil && $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Section Templates Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Save a section as a template from any workout first.")
                    )
                } else {
                    List(templates) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(systemName: template.sectionType.iconSymbolName)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name?.isEmpty == false ? template.name! : template.sectionType.fallbackSectionName)
                                        .foregroundStyle(Color.appInk)
                                    if let description = template.sectionDescription, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .themedListBackground()
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Import Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
