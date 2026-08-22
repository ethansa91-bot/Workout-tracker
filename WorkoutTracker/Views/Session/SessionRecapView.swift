import SwiftUI
import SwiftData

private struct SessionOverviewItem: Identifiable {
    let id: UUID
    /// 1-based position within its section, shown in place of the icon.
    let position: Int
    let title: String
    /// What this exercise is currently set to, shown in rust beneath its name.
    let summary: String?
    /// `nil` for EMOM/AMRAP entries, which have no settings of their own — those rows
    /// get no gear rather than an empty popover.
    let settings: ExerciseSettingsTarget?
    var color: Color?
}

/// `IconBadge`'s twin for a position number — same square, same tint treatment, so a
/// numbered row sits in the layout exactly where an icon badge did and a colored
/// follow-along step keeps showing its color.
private struct NumberBadge: View {
    let number: Int
    var tint: Color = .accentColor
    var size: CGFloat = 28

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
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
    @State private var sectionPendingEdit: WorkoutSection?
    @State private var sectionNameText = ""
    @State private var sectionDescriptionText = ""
    @State private var settingsPopoverSectionID: UUID?
    @State private var settingsPopoverItemID: UUID?
    /// Session-only — reopening the workout starts fully expanded again.
    @State private var collapsedSectionIDs: Set<UUID> = []
    /// Only one section can be in select mode at a time, so a selection never spans
    /// sections — clone/delete always act within a single section's list.
    @State private var selectModeSectionID: UUID?
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var pendingBatchDeleteSection: WorkoutSection?
    /// A single row deleted from its own gear, kept apart from `selectedItemIDs` so
    /// cancelling the confirm can't leave that row ticked in select mode.
    @State private var pendingDeleteItemID: UUID?
    /// What was collapsed before reorder collapsed everything, so leaving reorder puts
    /// the view back the way it was rather than discarding the user's arrangement.
    @State private var collapsedBeforeReorder: Set<UUID>?

    @State private var addExercisesSection: WorkoutSection?
    @State private var positionPickerItemID: UUID?
    @State private var positionPickerSectionID: UUID?
    @State private var scrollTargetSectionID: UUID?
    @State private var sectionPendingClone: WorkoutSection?
    @State private var cloneNameText = ""
    @State private var positionPickerValue = 1

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
        // Two containers on purpose. `List` is the only one that gives us drag-to-
        // reorder via `onMove`, but its backing collection view recycles a row whose
        // height changes a lot instead of animating it — which made collapsing snap and
        // the whole section blink out. `ScrollView` animates height properly, so it
        // handles normal browsing, and `List` is used only while reordering, where every
        // section is collapsed anyway and no height animates.
        Group {
            if editMode.isEditing {
                reorderList
            } else {
                browseScrollView
            }
        }
        .themedListBackground()
        .environment(\.editMode, $editMode)
        // The hero card already carries the name, and it's the editable one — a nav
        // title here would just duplicate it.
        .navigationTitle("")
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
        .alert(
            "Delete \(pendingDeleteCount) exercise\(pendingDeleteCount == 1 ? "" : "s")?",
            isPresented: Binding(
                get: { pendingBatchDeleteSection != nil },
                set: {
                    if !$0 {
                        pendingBatchDeleteSection = nil
                        pendingDeleteItemID = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) { confirmBatchDelete() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Rename Workout", isPresented: $showingRenamePrompt) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { renameWorkout() }
        }
        .alert("Clone Section", isPresented: Binding(
            get: { sectionPendingClone != nil },
            set: { if !$0 { sectionPendingClone = nil } }
        )) {
            TextField("Name", text: $cloneNameText)
            Button("Cancel", role: .cancel) { sectionPendingClone = nil }
            Button("Clone") { confirmCloneSection() }
        } message: {
            Text("The copy is inserted right after the original.")
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
        .sheet(item: $sectionPendingEdit) { section in
            sectionEditSheet(section)
        }
        .sheet(item: $addExercisesSection) { section in
            MultiExercisePickerView(existingExerciseIDs: existingExerciseIDs(for: section)) { exercises in
                addExercises(exercises, to: section)
            }
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

    /// Normal browsing: a plain scroll view, so a card's height change is an ordinary
    /// layout animation rather than a collection-view cell swap.
    private var browseScrollView: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                heroCard
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if !isLocked && workout.kind == .personalized {
                    sectionListControls
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }

                ForEach(workout.sortedSections) { section in
                    sectionCard(section)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .id(section.id)
                }

                if !allSectionsReady {
                    Text("Every section needs at least one exercise before this workout can be started.")
                        .font(.footnote)
                        .foregroundStyle(Color.appInkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
            }
            .padding(.top, 12)
        }
        .onChange(of: scrollTargetSectionID) { _, id in
            guard let id else { return }
            withAnimation { proxy.scrollTo(id, anchor: .top) }
            scrollTargetSectionID = nil
        }
        }
    }

    /// Reorder mode only — `onMove` needs a `List`. Sections are all collapsed here, so
    /// the row-height problem that rules `List` out for browsing never arises.
    private var reorderList: some View {
        List {
            // Its own Section, not the one holding the ForEach: `onMove` applies to the
            // whole section it's declared in, so a hero row sharing that section would
            // become a drop target for dragged cards.
            Section {
                heroCard
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
            }

            Section {
                sectionListControls
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                ForEach(workout.sortedSections) { section in
                    sectionCard(section)
                        .padding(.vertical, 4)
                        // Edit mode reserves a trailing gutter for the drag handle and
                        // squeezes the row to fit it. Negative trailing inset gives that
                        // width back so a card is the same size as when browsing; the
                        // handle then floats over the card's edge rather than beside it.
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: -22))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: reorderAction)
            }
        }
        // `.plain` drops the inset-grouped style's own side margins; edit mode still
        // reserves a leading gutter for the drag handles, which the negative inset
        // below cancels so cards keep the width they have while browsing.
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
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

    /// Header + exercise rows all inside one `.cardStyle()` container so the section's
    /// title and its exercises read as one visually connected unit, rather than a
    /// native List section header floating above loose rows.
    private func sectionCard(_ section: WorkoutSection) -> some View {
        let showsActions = !isLocked && !editMode.isEditing && workout.kind == .personalized
        let isCollapsed = collapsedSectionIDs.contains(section.id)

        let items = overviewItems(for: section)

        // Stack spacing is 0 and every element owns its padding, so nothing above the
        // divider depends on `isCollapsed` — the header subtree is byte-identical in
        // both states and cannot shift when the section opens or closes.
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(section)
                .padding(.bottom, 12)
            // Only the divider's presence changes with collapse — the header's own
            // padding stays fixed, so its geometry is identical either way and it can't
            // shift when toggling.
            if !isCollapsed {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 1)
            }

            // Always mounted, collapsed by height rather than by `if`. Inserting and
            // removing the subtree makes SwiftUI drop it in one frame instead of
            // animating, which is what made the section blink out; animating a real
            // height gives a continuous change instead.
            //
            // No opacity fade here on purpose: fading makes the rows dissolve in place
            // while they're still drawn over the header. Letting the clip alone hide
            // them means they slide up and disappear behind the header edge, which is
            // the "retracting behind the header" look rather than a ghost passing over
            // it. `.clipMask` keeps the shrinking frame as the mask so rows are cut off
            // at the divider rather than escaping upward.
            collapsibleBody(section, items: items, showsActions: showsActions)
                .frame(maxHeight: isCollapsed ? 0 : .infinity, alignment: .top)
                .clipped()
        }
        .padding(16)
        .cardStyle()
        .animation(.easeInOut(duration: 0.25), value: isCollapsed)
    }

    /// Add Exercise normally; in select mode the same row turns into the batch
    /// actions for whatever is ticked, with Select/Done anchoring the left edge.
    @ViewBuilder
    private func addExerciseRow(_ section: WorkoutSection) -> some View {
        let inSelectMode = selectModeSectionID == section.id
        let count = selectedItemIDs.count

        HStack {
            Button(inSelectMode ? "Done" : "Select") {
                toggleSelectMode(section)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(Color.appAccent)

            Spacer()

            if inSelectMode {
                // Four actions plus Select/Done doesn't fit with word labels on a narrow
                // phone, so each is an icon with its count beside it.
                selectAction(
                    "chevron.up",
                    count: count,
                    tint: Color.appAccent,
                    disabled: isSelectionAtStart(section)
                ) {
                    moveSelection(in: section, by: -1)
                }
                Spacer()
                selectAction(
                    "chevron.down",
                    count: count,
                    tint: Color.appAccent,
                    disabled: isSelectionAtEnd(section)
                ) {
                    moveSelection(in: section, by: 1)
                }
                Spacer()
                selectAction("doc.on.doc", count: count, tint: Color.appAccent) {
                    cloneSelection(in: section)
                }
                Spacer()
                selectAction("trash", count: count, tint: Color.appDanger) {
                    pendingBatchDeleteSection = section
                }
            } else {
                Button {
                    addExercisesSection = section
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
            }

            Spacer()
        }
    }

    private func selectAction(
        _ symbol: String,
        count: Int,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text("\(count)")
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .disabled(selectedItemIDs.isEmpty || disabled)
    }

    private func toggleSelectMode(_ section: WorkoutSection) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectModeSectionID == section.id {
                selectModeSectionID = nil
            } else {
                selectModeSectionID = section.id
            }
            // Entering or leaving always starts from a clean slate, which is also what
            // keeps a selection from surviving a jump to another section.
            selectedItemIDs.removeAll()
        }
    }

    private func toggleSelected(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    // MARK: - Per-row and batch actions

    private func cloneItems(_ ids: Set<UUID>, in section: WorkoutSection) {
        guard !ids.isEmpty else { return }
        do {
            switch section.sectionType {
            case .time:
                try WorkoutSectionCloningService.cloneTimeSteps(in: section, ids: ids, context: context)
            case .rep:
                try WorkoutSectionCloningService.cloneRepExercises(in: section, ids: ids, context: context)
            case .emom, .amrap:
                try WorkoutSectionCloningService.cloneQuickExercises(in: section, ids: ids, context: context)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItems(_ ids: Set<UUID>, in section: WorkoutSection) {
        guard !ids.isEmpty else { return }
        do {
            switch section.sectionType {
            case .time:
                for step in section.sortedTimeSteps where ids.contains(step.id) {
                    try WorkoutEditingService.deleteTimeStep(step, from: section, context: context)
                }
            case .rep:
                for entry in section.sortedRepExercises where ids.contains(entry.id) {
                    try WorkoutEditingService.deleteRepExercise(entry, from: section, context: context)
                }
            case .emom, .amrap:
                for entry in section.sortedQuickExercises where ids.contains(entry.id) {
                    try WorkoutEditingService.deleteQuickExercise(entry, from: section, context: context)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Moving rows
    //
    // Display rows are not the model array. A `.time` section hides its Get Ready step
    // from the list but still keeps it at index 0, so every move has to be expressed in
    // model indices — moving by display index would push Get Ready out of first place
    // and the section would start mid-exercise.

    /// The section's rows in model order, with the ones the list never shows removed.
    private func displayRowIDs(in section: WorkoutSection) -> [UUID] {
        switch section.sectionType {
        case .time: return section.sortedTimeSteps.filter { $0.stepType != .getReady }.map(\.id)
        case .rep: return section.sortedRepExercises.map(\.id)
        case .emom, .amrap: return section.sortedQuickExercises.map(\.id)
        }
    }

    /// Every row in model order, Get Ready included.
    private func modelRowIDs(in section: WorkoutSection) -> [UUID] {
        switch section.sectionType {
        case .time: return section.sortedTimeSteps.map(\.id)
        case .rep: return section.sortedRepExercises.map(\.id)
        case .emom, .amrap: return section.sortedQuickExercises.map(\.id)
        }
    }

    private func applyMove(in section: WorkoutSection, from source: IndexSet, to destination: Int) {
        do {
            switch section.sectionType {
            case .time:
                try WorkoutEditingService.moveTimeSteps(in: section, from: source, to: destination, context: context)
            case .rep:
                try WorkoutEditingService.moveRepExercises(in: section, from: source, to: destination, context: context)
            case .emom, .amrap:
                try WorkoutEditingService.moveQuickExercises(in: section, from: source, to: destination, context: context)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves `ids` (kept in their existing relative order) so they land starting at
    /// `displayPosition`, a 1-based index into the *visible* rows.
    private func move(ids: Set<UUID>, in section: WorkoutSection, toDisplayPosition displayPosition: Int) {
        let display = displayRowIDs(in: section)
        let model = modelRowIDs(in: section)
        guard !ids.isEmpty, !display.isEmpty else { return }

        let clamped = min(max(displayPosition, 1), display.count)
        // The display row the block should end up sitting at, resolved to its position
        // in the model array.
        let anchorID = display[clamped - 1]
        guard let anchorModelIndex = model.firstIndex(of: anchorID) else { return }

        let sourceIndices = IndexSet(model.indices.filter { ids.contains(model[$0]) })
        guard !sourceIndices.isEmpty else { return }

        // `move(fromOffsets:toOffset:)` treats the destination as a gap *before* the
        // element currently there, so moving downward needs one past the anchor.
        let movingDown = (sourceIndices.min() ?? 0) < anchorModelIndex
        let destination = movingDown ? anchorModelIndex + 1 : anchorModelIndex

        applyMove(in: section, from: sourceIndices, to: destination)
    }

    /// Shifts the selected rows one slot, as a block. Non-contiguous picks gather
    /// together at the destination — `move(ids:in:toDisplayPosition:)` preserves the
    /// selection's relative order, so the block keeps the order shown on screen.
    ///
    /// The selection deliberately survives, so the same rows can be walked up or down
    /// the list with repeated taps instead of being re-picked each time.
    private func moveSelection(in section: WorkoutSection, by offset: Int) {
        let display = displayRowIDs(in: section)
        let positions = display.indices.filter { selectedItemIDs.contains(display[$0]) }
        guard let first = positions.first, let last = positions.last else { return }

        // Anchor on whichever end leads the move, so a block travelling down lands past
        // the row it displaces rather than on top of it.
        let target = offset < 0 ? first + offset : last + offset
        let clamped = min(max(target, 0), display.count - 1)
        move(ids: selectedItemIDs, in: section, toDisplayPosition: clamped + 1)
    }

    /// Nothing above the selection to swap with — the Up button has no work to do.
    private func isSelectionAtStart(_ section: WorkoutSection) -> Bool {
        guard let firstID = displayRowIDs(in: section).first else { return true }
        return selectedItemIDs.contains(firstID)
    }

    private func isSelectionAtEnd(_ section: WorkoutSection) -> Bool {
        guard let lastID = displayRowIDs(in: section).last else { return true }
        return selectedItemIDs.contains(lastID)
    }

    /// The copies are new rows and the originals keep their ids, so the selection still
    /// points at the originals — cloning twice gives two copies of the same rows rather
    /// than copies of copies.
    private func cloneSelection(in section: WorkoutSection) {
        cloneItems(selectedItemIDs, in: section)
    }

    /// How many rows the pending confirm would remove — one when it came from a row's
    /// own gear, otherwise everything ticked in select mode.
    private var pendingDeleteCount: Int {
        pendingDeleteItemID != nil ? 1 : selectedItemIDs.count
    }

    private func confirmBatchDelete() {
        guard let section = pendingBatchDeleteSection else { return }
        if let single = pendingDeleteItemID {
            deleteItems([single], in: section)
        } else {
            deleteItems(selectedItemIDs, in: section)
            selectedItemIDs.removeAll()
        }
        pendingDeleteItemID = nil
        pendingBatchDeleteSection = nil
    }

    private func addRest(after step: TimeSectionStep) {
        do {
            _ = try WorkoutEditingService.addRestStep(after: step, durationSeconds: 30, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var allCollapsed: Bool {
        !workout.sortedSections.isEmpty
            && collapsedSectionIDs.count >= workout.sortedSections.count
    }

    /// Reordering full-height cards means dragging past a lot of content, so entering
    /// reorder collapses everything to make the drag targets small — and leaving it
    /// restores whatever was open beforehand.
    private func toggleReorderMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if editMode.isEditing {
                editMode = .inactive
                if let previous = collapsedBeforeReorder {
                    collapsedSectionIDs = previous
                    collapsedBeforeReorder = nil
                }
            } else {
                // Select mode's row lives inside the region about to collapse, so it
                // would otherwise be stranded out of reach.
                selectModeSectionID = nil
                selectedItemIDs.removeAll()

                collapsedBeforeReorder = collapsedSectionIDs
                collapsedSectionIDs = Set(workout.sortedSections.map(\.id))
                editMode = .active
            }
        }
    }

    private func toggleCollapseAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if allCollapsed {
                collapsedSectionIDs.removeAll()
            } else {
                collapsedSectionIDs = Set(workout.sortedSections.map(\.id))
            }
        }
    }

    private func toggleCollapsed(_ section: WorkoutSection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if collapsedSectionIDs.contains(section.id) {
                collapsedSectionIDs.remove(section.id)
            } else {
                collapsedSectionIDs.insert(section.id)
            }
        }
    }

    /// Everything below the header divider: the Select/Add row, the line enclosing the
    /// list from above, and the exercise rows. One subtree, so the collapse conditional
    /// wraps exactly this and nothing else.
    @ViewBuilder
    private func collapsibleBody(
        _ section: WorkoutSection,
        items: [SessionOverviewItem],
        showsActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsActions {
                addExerciseRow(section)
            }
            // Only when the Select/Add row is above it — that row is what this line
            // separates from the list. Without it (reorder mode, locked workouts) the
            // header's own divider already closes the header off, and drawing both
            // leaves two hairlines stacked with nothing between them.
            if showsActions, !items.isEmpty {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
            }
            ForEach(items) { item in
                overviewItemRow(
                    item,
                    section: section,
                    showsActions: showsActions,
                    isLast: item.id == items.last?.id,
                    itemCount: items.count
                )
            }
        }
        .padding(.top, 12)
    }

    /// Name + pencil on row 1 (alongside the section's own actions), description on
    /// row 2, and the timing settings the gear popover controls summarised on row 3 —
    /// so what Rounds/Autostart/Repeat are currently set to is readable without
    /// opening anything.
    @ViewBuilder
    private func sectionHeader(_ section: WorkoutSection) -> some View {
        let showsActions = !isLocked && !editMode.isEditing
        // The chevron outlives reorder mode: the header must look and behave the same
        // whatever mode you're in, and expanding a section to check it mid-reorder is
        // harmless in a way that Delete or the settings gear is not.
        // Also off while reordering: dragging is the only interaction that mode is for,
        // and everything is collapsed on entry anyway.
        let showsChevron = !isLocked && workout.kind == .personalized && !editMode.isEditing

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if workout.kind == .personalized {
                    HStack(spacing: 8) {
                        // Same chip as an exercise row's number, in gray so the two
                        // levels stay visually distinct.
                        if showsActions, workout.sortedSections.count > 1 {
                            Button {
                                positionPickerValue = sectionIndex(section) + 1
                                positionPickerSectionID = section.id
                            } label: {
                                NumberBadge(number: sectionIndex(section) + 1, tint: Color.appInkMuted)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: sectionPositionBinding(for: section.id)) {
                                sectionPositionPicker(section: section)
                            }
                        } else {
                            NumberBadge(number: sectionIndex(section) + 1, tint: Color.appInkMuted)
                        }

                        Text(sectionTitle(section))
                            .font(.headline)
                            .foregroundStyle(Color.appInk)
                        if showsActions {
                            Button {
                                beginEditingSection(section)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
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
                // adding a new one — Clone/Delete/Settings hide entirely so a stray tap
                // can't do anything else mid-reorder.
                if showsActions {
                    if workout.kind == .personalized {
                        // Clone and Delete moved into the gear popover, matching how an
                        // exercise row's actions work. Save-as-template stays here: it's
                        // neither of those, and has no exercise-level equivalent.
                        Button {
                            saveAsTemplate(section)
                        } label: {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appInkMuted)

                        // The popover has to be attached here rather than on the card —
                        // SwiftUI anchors a popover to the view carrying the modifier,
                        // and it should point at the gear that opened it.
                        Button {
                            settingsPopoverSectionID = section.id
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appRust)
                        .popover(isPresented: settingsPopoverBinding(for: section)) {
                            SectionSettingsPopover(
                                section: section,
                                context: context,
                                onError: { errorMessage = $0 },
                                onClone: {
                                    settingsPopoverSectionID = nil
                                    beginCloningSection(section)
                                },
                                onDelete: {
                                    settingsPopoverSectionID = nil
                                    sectionPendingDeletion = section
                                }
                            )
                        }

                    } else {
                        // Follow Along/By Reps has only this one action, where text reads
                        // more clearly than an icon on its own. A plain Button, not a
                        // NavigationLink — List auto-adds a trailing disclosure chevron to
                        // any row containing one, even a small inline element.
                        Button {
                            manageExercisesSection = section
                        } label: {
                            Text("Manage Exercises")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.appAccent)
                        .buttonStyle(.plain)
                    }
                }

                // Last in the row and gated separately, so its position never shifts as
                // the other icons come and go.
                if showsChevron {
                    Button {
                        toggleCollapsed(section)
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(collapsedSectionIDs.contains(section.id) ? -90 : 0))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appInkMuted)
                }
            }

            if workout.kind == .personalized {
                if let description = section.sectionDescription, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Color.appInkMuted)
                }

                Text(sectionSettingsSummary(section))
                    .font(.caption)
                    .foregroundStyle(Color.appRust)
            }
        }
    }

    /// `.popover(item:)` would re-present on every section whose card is on screen, so
    /// the open state is tracked by id and narrowed to a per-section Bool here.
    private func settingsPopoverBinding(for section: WorkoutSection) -> Binding<Bool> {
        Binding(
            get: { settingsPopoverSectionID == section.id },
            set: { if !$0 && settingsPopoverSectionID == section.id { settingsPopoverSectionID = nil } }
        )
    }

    private func beginEditingSection(_ section: WorkoutSection) {
        sectionNameText = section.name ?? ""
        sectionDescriptionText = section.sectionDescription ?? ""
        sectionPendingEdit = section
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

                HStack {
                    // One button, not two — it collapses whatever is still open, and
                    // only offers Expand once everything is already collapsed.
                    if !workout.sortedSections.isEmpty && !editMode.isEditing {
                        Button {
                            toggleCollapseAll()
                        } label: {
                            Image(systemName: allCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.glass)
                    }

                    Spacer()

                    if workout.sortedSections.count > 1 {
                        Button {
                            toggleReorderMode()
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

    /// Stays on this page rather than pushing the old section editor: the new section
    /// is the only one left open, and the view scrolls to put it in focus.
    private func createSection(name: String, description: String?, type: WorkoutSectionType) {
        do {
            let section = try WorkoutEditingService.addSection(to: workout, type: type, name: name, description: description, context: context)
            withAnimation(.easeInOut(duration: 0.25)) {
                collapsedSectionIDs = Set(workout.sortedSections.map(\.id)).subtracting([section.id])
            }
            scrollTargetSectionID = section.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginCloningSection(_ section: WorkoutSection) {
        cloneNameText = sectionTitle(section)
        sectionPendingClone = section
    }

    /// The copy takes the name entered in the prompt rather than inheriting the
    /// original's, which used to leave two identically-named sections in the list.
    private func confirmCloneSection() {
        guard let section = sectionPendingClone else { return }
        let trimmed = cloneNameText.trimmingCharacters(in: .whitespaces)
        do {
            let copy = try WorkoutSectionCloningService.cloneSection(section, context: context)
            if !trimmed.isEmpty {
                try WorkoutEditingService.rename(copy, to: trimmed, context: context)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        sectionPendingClone = nil
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

    /// Same name + description form the section editors present from their hero card,
    /// so editing a section reads identically whichever screen you reach it from.
    private func sectionEditSheet(_ section: WorkoutSection) -> some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $sectionNameText)
                }
                Section("Description") {
                    TextEditor(text: $sectionDescriptionText)
                        .frame(minHeight: 160)
                }
            }
            .themedListBackground()
            .navigationTitle("Edit Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { sectionPendingEdit = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSectionEdits(section) }
                }
            }
        }
    }

    private func saveSectionEdits(_ section: WorkoutSection) {
        let trimmedName = sectionNameText.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = sectionDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedName.isEmpty {
                try WorkoutEditingService.rename(section, to: trimmedName, context: context)
            }
            try WorkoutEditingService.updateDescription(section, to: trimmedDescription.isEmpty ? nil : trimmedDescription, context: context)
            sectionPendingEdit = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func existingExerciseIDs(for section: WorkoutSection) -> Set<UUID> {
        switch section.sectionType {
        case .time: return Set(section.sortedTimeSteps.compactMap { $0.exercise?.id })
        case .rep: return Set(section.sortedRepExercises.compactMap { $0.exercise?.id })
        case .emom, .amrap: return Set(section.sortedQuickExercises.compactMap { $0.exercise?.id })
        }
    }

    /// Appends with the same per-type defaults each section editor uses, so an exercise
    /// added from here is indistinguishable from one added inside the editor.
    private func addExercises(_ exercises: [Exercise], to section: WorkoutSection) {
        for exercise in exercises {
            do {
                switch section.sectionType {
                case .time:
                    try WorkoutEditingService.addTimeStep(to: section, stepType: .exercise, exercise: exercise, durationSeconds: 30, context: context)
                case .rep:
                    try WorkoutEditingService.addRepExercise(to: section, exercise: exercise, targetSets: 3, customRestSeconds: nil, context: context)
                case .emom, .amrap:
                    try WorkoutEditingService.addQuickExercise(to: section, exercise: exercise, context: context)
                }
            } catch {
                errorMessage = error.localizedDescription
                break
            }
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
            // Get Ready is edited from the section's gear instead of appearing here —
            // it's still a real step the runner plays, just not one of the exercises.
            let steps = section.sortedTimeSteps.filter { $0.stepType != .getReady }
            return steps.enumerated().map { index, step in
                SessionOverviewItem(
                    id: step.id,
                    position: index + 1,
                    title: overviewTitle(for: step),
                    summary: exerciseSettingsSummary(.timeStep(step)),
                    settings: .timeStep(step),
                    // Rest has no `effectiveColor` (nil) — gray, not the green default
                    // the badge would otherwise fall back to.
                    color: step.stepType == .exercise ? (step.effectiveColor?.color ?? .accentColor) : Color.secondary
                )
            }
        case .rep:
            return section.sortedRepExercises.enumerated().map { index, entry in
                SessionOverviewItem(
                    id: entry.id,
                    position: index + 1,
                    title: entry.exercise?.displayName ?? "Exercise",
                    summary: exerciseSettingsSummary(.repEntry(entry)),
                    settings: .repEntry(entry)
                )
            }
        case .emom, .amrap:
            return section.sortedQuickExercises.enumerated().map { index, entry in
                SessionOverviewItem(
                    id: entry.id,
                    position: index + 1,
                    title: entry.exercise?.displayName ?? "Exercise",
                    summary: exerciseSettingsSummary(.quickEntry(entry)),
                    settings: .quickEntry(entry)
                )
            }
        }
    }

    private func overviewTitle(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    /// Name over a rust line of whatever that exercise is currently set to, with its
    /// own gear — the same shape the section header above it uses, one level down.
    private func overviewItemRow(
        _ item: SessionOverviewItem,
        section: WorkoutSection,
        showsActions: Bool,
        isLast: Bool,
        itemCount: Int
    ) -> some View {
        let inSelectMode = showsActions && selectModeSectionID == section.id
        let isSelected = selectedItemIDs.contains(item.id)
        // Whatever the row is currently the subject of — ticked, or holding an open
        // popover — gets the same light-gray backing so it's obvious which row an
        // action will apply to.
        let isActive = isSelected
            || settingsPopoverItemID == item.id
            || positionPickerItemID == item.id

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if inSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.appAccent : Color.appInkMuted)
                }

                if showsActions, !inSelectMode, itemCount > 1 {
                    Button {
                        positionPickerValue = item.position
                        positionPickerItemID = item.id
                    } label: {
                        NumberBadge(number: item.position, tint: item.color ?? .accentColor)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: positionPickerBinding(for: item.id)) {
                        positionPicker(section: section, item: item, count: itemCount)
                    }
                } else {
                    NumberBadge(number: item.position, tint: item.color ?? .accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    if let summary = item.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(Color.appRust)
                    }
                }
                Spacer()

                // One meaning per row: while picking rows for a batch action, the gear
                // would be a second, conflicting tap target.
                if showsActions, !inSelectMode, let settings = item.settings {
                    Button {
                        settingsPopoverItemID = item.id
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appAccent)
                    .popover(isPresented: exerciseSettingsBinding(for: item.id)) {
                        ExerciseSettingsPopover(
                            target: settings,
                            context: context,
                            onClone: {
                                settingsPopoverItemID = nil
                                cloneItems([item.id], in: section)
                            },
                            onDelete: {
                                settingsPopoverItemID = nil
                                pendingDeleteItemID = item.id
                                pendingBatchDeleteSection = section
                            },
                            onAddRest: addRestAction(for: settings)
                        )
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isActive ? Color.appHighlightGray : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                guard inSelectMode else { return }
                toggleSelected(item.id)
            }

            if !isLast {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
            }
        }
    }

    /// Only follow-along steps can gain a rest after them — every other row passes nil,
    /// which is what hides the button rather than showing a dead one.
    private func addRestAction(for target: ExerciseSettingsTarget) -> (() -> Void)? {
        guard case .timeStep(let step) = target, step.stepType == .exercise else { return nil }
        return {
            settingsPopoverItemID = nil
            addRest(after: step)
        }
    }

    private func sectionIndex(_ section: WorkoutSection) -> Int {
        workout.sortedSections.firstIndex { $0.id == section.id } ?? 0
    }

    private func sectionPositionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { positionPickerSectionID == id },
            set: { if !$0 && positionPickerSectionID == id { positionPickerSectionID = nil } }
        )
    }

    /// Same wheel as an exercise's, routed through `moveSections` instead.
    private func sectionPositionPicker(section: WorkoutSection) -> some View {
        let sections = workout.sortedSections
        let current = sectionIndex(section)

        return VStack(spacing: 8) {
            Text("Change position")
                .font(.headline)
                .foregroundStyle(Color.appInk)
            Picker("", selection: $positionPickerValue) {
                ForEach(1...max(sections.count, 1), id: \.self) { position in
                    Text("\(position)").tag(position)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            Button {
                let target = min(max(positionPickerValue - 1, 0), sections.count - 1)
                if target != current {
                    // `move(fromOffsets:toOffset:)` treats the destination as the gap
                    // before that element, so a downward move needs one past it.
                    let destination = target > current ? target + 1 : target
                    do {
                        try WorkoutEditingService.moveSections(in: workout, from: IndexSet(integer: current), to: destination, context: context)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                positionPickerSectionID = nil
            } label: {
                Text("Save")
                    .foregroundStyle(Color.appAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.appAccent.opacity(0.25))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
        .frame(width: 220, height: 280)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }

    private func positionPickerBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { positionPickerItemID == id },
            set: { if !$0 && positionPickerItemID == id { positionPickerItemID = nil } }
        )
    }

    /// Native wheel of every position in the section, current one preselected — pick a
    /// different number and the exercise moves there.
    private func positionPicker(section: WorkoutSection, item: SessionOverviewItem, count: Int) -> some View {
        VStack(spacing: 8) {
            Text("Change position")
                .font(.headline)
                .foregroundStyle(Color.appInk)
            Picker("", selection: $positionPickerValue) {
                ForEach(1...max(count, 1), id: \.self) { position in
                    Text("\(position)").tag(position)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()

            // Committing on every wheel tick would move the row three times on the way
            // from 4 to 1, churning the list under the popover — so nothing happens
            // until Save. Dismissing by tapping outside leaves the order untouched.
            Button {
                if positionPickerValue != item.position {
                    move(ids: [item.id], in: section, toDisplayPosition: positionPickerValue)
                }
                positionPickerItemID = nil
            } label: {
                Text("Save")
                    .foregroundStyle(Color.appAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.appAccent.opacity(0.25))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
        .frame(width: 220, height: 280)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Same reason as `settingsPopoverBinding(for:)` — `.popover(item:)` would try to
    /// present on every row on screen, so the open row is tracked by id.
    private func exerciseSettingsBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { settingsPopoverItemID == id },
            set: { if !$0 && settingsPopoverItemID == id { settingsPopoverItemID = nil } }
        )
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
