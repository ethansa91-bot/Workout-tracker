import SwiftUI
import SwiftData


/// Tapping a workout in the list lands here: a quick recap of everything in it, plus
/// the ability to start it (or resume a paused session, or jump into editing).
struct SessionRecapView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context

    @State private var activeSession: WorkoutSession?
    @State private var showingSupersedeConfirm = false
    @State private var sessionSoundProfile: TimerSoundProfile?
    /// Supplied by the parent that pushed this screen, which owns the navigation path —
    /// cloning a locked workout puts the copy in this screen's place rather than
    /// stacking it on top of a workout the user was just told they can't edit.
    var onReplaceWithClone: ((Workout) -> Void)?

    @State private var showingLockedNotice = false
    @State private var showingClonePrompt = false
    @State private var cloneWorkoutNameText = ""
    @State private var showingRenamePrompt = false
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var sectionPendingDeletion: WorkoutSection?
    @State private var showingDescriptionEditor = false
    @State private var descriptionText = ""
    @State private var sectionPendingSaveAsTemplate: WorkoutSection?
    @State private var templateNameText = ""
    @State private var showingImportTemplateSheet = false
    @State private var showingNewSectionSheet = false
    /// Session-only — reopening the workout starts fully expanded again.
    @State private var collapsedSectionIDs: Set<UUID> = []
    /// Owned here rather than inside the card because the card renders as two instances
    /// (header band and exercise rows) — `@State` on the card would give each half its
    /// own copy, which is what broke select mode.
    ///
    /// Only one section can be in select mode at a time, so a selection never spans
    /// sections — clone/delete always act within a single section's list.
    /// Section-level select mode. Plain state, unlike the exercise-level equivalent —
    /// nothing here is split across two view instances.
    @State private var inSectionSelectMode = false
    /// What was collapsed before select mode collapsed everything, so leaving puts the
    /// view back the way it was rather than discarding the user's arrangement.
    @State private var collapsedBeforeSelect: Set<UUID>?
    @State private var selectedSectionIDs: Set<UUID> = []
    @State private var showingSectionBatchDeleteConfirm = false
    @State private var selectModeSectionID: UUID?
    @State private var selectedItemIDsBySection: [UUID: Set<UUID>] = [:]
    @State private var batchDeleteSectionID: UUID?
    /// A single row deleted from its own gear, kept apart from `selectedItemIDs` so
    /// cancelling the confirm can't leave that row ticked in select mode.
    @State private var pendingDeleteItemID: UUID?
    /// Bulk collapse/expand jumps straight to the result: N sections animating their
    /// heights at once against a reflowing scroll stack reads as an accordion ripple
    /// rather than as one gesture. The per-section chevron keeps its animation, so this
    /// gates the card's implicit `.animation(value:)` instead of removing it.
    @State private var suppressCollapseAnimation = false

    @State private var scrollTargetSectionID: UUID?
    @State private var sectionPendingClone: WorkoutSection?
    @State private var cloneNameText = ""

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
        browseScrollView
        .themedListBackground()
        // Hero and controls ride together as an inset rather than as the first rows of
        // the scroll stack, so they stay put while the sections scroll under them.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                heroCard
                sectionListControls
            }
        }
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
        .alert(
            "Delete \(selectedSectionIDs.count) section\(selectedSectionIDs.count == 1 ? "" : "s")?",
            isPresented: $showingSectionBatchDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { confirmDeleteSelectedSections() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(selectedSectionExerciseCount == 0
                 ? "This cannot be undone."
                 : "The \(selectedSectionExerciseCount) exercise\(selectedSectionExerciseCount == 1 ? "" : "s") inside will be deleted too. This cannot be undone.")
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
        .alert("Workout Already Used", isPresented: $showingLockedNotice) {
            Button("Clone & Edit") {
                cloneWorkoutNameText = "\(workout.name) Copy"
                showingClonePrompt = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This workout has already been used in a session, so editing it would change what that history means. Clone it to get an editable copy.")
        }
        .alert("Clone & Edit", isPresented: $showingClonePrompt) {
            TextField("Name", text: $cloneWorkoutNameText)
            Button("Cancel", role: .cancel) { }
            Button("Clone") { cloneAndEdit() }
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
            // Pinned headers so a section's gray band stays visible while its own
            // exercises scroll under it, the way Schedule's day headers do — a `List`
            // gives that free, a `ScrollView` needs it asked for. The 2pt spacing lets
            // the cream ground show between bands so a fully-collapsed workout doesn't
            // read as one solid gray block.
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(workout.sortedSections) { section in
                    Section {
                        sectionCard(section, part: .body)
                    } header: {
                        // Padding inside the pinned header, not stack spacing between
                        // sections: it has to travel with the band when pinned, and it
                        // has to carry the cream ground or scrolled rows show through
                        // the gap above a pinned header.
                        sectionCard(section, part: .header)
                            .padding(.top, 12)
                            .background(Color.appBackground)
                    }
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
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
                .tint(Color.appAccent)

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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
                .tint(Color.appAccent)
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

    /// The same full-width accent band the runners open with, pinned above the section
    /// list rather than scrolling away with it — so the workout you're editing stays
    /// named on screen however far down the sections you are.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(workout.name)
                    .font(.appSerif(.title2))
                    .foregroundStyle(.white)
                if !isLocked {
                    Button {
                        renameText = workout.name
                        showingRenamePrompt = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    // Says why the editing affordances are missing, rather than leaving
                    // their absence to be puzzled over.
                    Button {
                        showingLockedNotice = true
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            Text(heroInfoLine)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            descriptionRow
        }
        .headerBandStyle()
    }

    @ViewBuilder
    private var descriptionRow: some View {
        if let notes = workout.notes, !notes.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                if !isLocked {
                    Button {
                        descriptionText = notes
                        showingDescriptionEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.top, 2)
        } else if !isLocked {
            Button("Add Description") {
                descriptionText = ""
                showingDescriptionEditor = true
            }
            .font(.footnote)
            // On the accent fill the accent itself is invisible — underlined white
            // keeps it reading as the one tappable thing in the band.
            .foregroundStyle(.white)
            .underline()
            .padding(.top, 2)
        }
    }

    private var heroInfoLine: String {
        let exerciseCount = workout.sortedSections.reduce(0) { $0 + sectionExerciseCount($1) }
        let exercisesText = "\(exerciseCount) Exercise\(exerciseCount == 1 ? "" : "s")"
        let sectionCount = workout.sortedSections.count
        var line = "\(sectionCount) Section\(sectionCount == 1 ? "" : "s") · \(exercisesText) · \(workout.listTypeLabel)"
        // Omitted rather than shown as "~0 min" on a workout with nothing in it yet.
        let estimate = estimatedWorkoutSeconds(workout)
        if estimate > 0 {
            line += " · \(formattedEstimate(estimate))"
        }
        return line
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

    /// One section's card, rendered by the component the standalone-section screen also
    /// uses so the two can't drift. Everything cross-section — where this card sits
    /// among its siblings, and the actions that only make sense with siblings — is
    /// handed over in `SectionCardSiblings`.
    private func sectionCard(_ section: WorkoutSection, part: SectionCardView.Part = .whole) -> some View {
        SectionCardView(
            section: section,
            isCollapsed: collapsedBinding(for: section),
            inSectionSelectMode: inSectionSelectMode,
            isSectionSelected: selectedSectionIDs.contains(section.id),
            onToggleSectionSelected: { toggleSectionSelected(section.id) },
            siblings: SectionCardSiblings(
                index: sectionIndex(section),
                count: workout.sortedSections.count,
                onReorder: { position in moveSection(section, toPosition: position) },
                onDelete: { sectionPendingDeletion = section },
                onClone: { beginCloningSection(section) },
                onSaveAsTemplate: { saveAsTemplate(section) }
            ),
            suppressCollapseAnimation: suppressCollapseAnimation,
            part: part,
            onError: { errorMessage = $0 },
            inSelectMode: selectModeBinding(for: section),
            selectedItemIDs: selectedItemsBinding(for: section),
            showingBatchDeleteConfirm: batchDeleteBinding(for: section),
            pendingDeleteItemID: $pendingDeleteItemID
        )
    }

    /// The card owns its open/closed state through this binding, so a single chevron tap
    /// writes straight back into the set the collapse-all button reads.
    /// Entering select mode on one section leaves any other — the id doubles as the
    /// flag, so it can't be on in two places at once.
    private func selectModeBinding(for section: WorkoutSection) -> Binding<Bool> {
        Binding(
            get: { selectModeSectionID == section.id },
            set: { on in
                if on {
                    selectModeSectionID = section.id
                } else if selectModeSectionID == section.id {
                    selectModeSectionID = nil
                }
            }
        )
    }

    private func selectedItemsBinding(for section: WorkoutSection) -> Binding<Set<UUID>> {
        Binding(
            get: { selectedItemIDsBySection[section.id] ?? [] },
            set: { selectedItemIDsBySection[section.id] = $0 }
        )
    }

    private func batchDeleteBinding(for section: WorkoutSection) -> Binding<Bool> {
        Binding(
            get: { batchDeleteSectionID == section.id },
            set: { on in
                if on {
                    batchDeleteSectionID = section.id
                } else if batchDeleteSectionID == section.id {
                    batchDeleteSectionID = nil
                }
            }
        )
    }

    private func collapsedBinding(for section: WorkoutSection) -> Binding<Bool> {
        Binding(
            get: { collapsedSectionIDs.contains(section.id) },
            set: { collapsed in
                if collapsed {
                    collapsedSectionIDs.insert(section.id)
                } else {
                    collapsedSectionIDs.remove(section.id)
                }
            }
        )
    }

    /// Moves a section to a 1-based position among its siblings.
    private func moveSection(_ section: WorkoutSection, toPosition position: Int) {
        let sections = workout.sortedSections
        let current = sectionIndex(section)
        let target = min(max(position - 1, 0), sections.count - 1)
        guard target != current else { return }
        // `move(fromOffsets:toOffset:)` treats the destination as the gap before that
        // element, so a downward move needs one past it.
        let destination = target > current ? target + 1 : target
        do {
            try WorkoutEditingService.moveSections(in: workout, from: IndexSet(integer: current), to: destination, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    private var allCollapsed: Bool {
        !workout.sortedSections.isEmpty
            && collapsedSectionIDs.count >= workout.sortedSections.count
    }

    /// Applies a change that flips many sections at once with no animation at all.
    ///
    /// Two things have to be switched off, not one: `disablesAnimations` on the
    /// transaction kills any ambient animation around the mutation, and the flag gates
    /// each card's own implicit `.animation(value:)` — which `withAnimation(nil)` alone
    /// would not override. The flag is cleared after the resulting layout pass so the
    /// per-section chevron animates normally again.
    private func withoutCollapseAnimation(_ mutate: () -> Void) {
        suppressCollapseAnimation = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, mutate)
        DispatchQueue.main.async { suppressCollapseAnimation = false }
    }


    /// Selecting is about the sections themselves, so their exercises collapse out of
    /// the way — only the headers being picked stay on screen. Leaving restores whatever
    /// was open beforehand.
    private func toggleSectionSelectMode() {
        withoutCollapseAnimation {
            if inSectionSelectMode {
                if let previous = collapsedBeforeSelect {
                    collapsedSectionIDs = previous
                    collapsedBeforeSelect = nil
                }
            } else {
                collapsedBeforeSelect = collapsedSectionIDs
                collapsedSectionIDs = Set(workout.sortedSections.map(\.id))
            }
            inSectionSelectMode.toggle()
            // Entering or leaving always starts from a clean slate.
            selectedSectionIDs.removeAll()
        }
    }

    private func toggleSectionSelected(_ id: UUID) {
        if selectedSectionIDs.contains(id) {
            selectedSectionIDs.remove(id)
        } else {
            selectedSectionIDs.insert(id)
        }
    }

    private var isSectionSelectionAtStart: Bool {
        guard let first = workout.sortedSections.first else { return true }
        return selectedSectionIDs.contains(first.id)
    }

    private var isSectionSelectionAtEnd: Bool {
        guard let last = workout.sortedSections.last else { return true }
        return selectedSectionIDs.contains(last.id)
    }

    /// Shifts the selected sections one slot as a block, anchoring on whichever end
    /// leads the move so a block travelling down lands past what it displaces. The
    /// selection survives, so the same sections can be walked with repeated taps.
    private func moveSectionSelection(by offset: Int) {
        let sections = workout.sortedSections
        let positions = sections.indices.filter { selectedSectionIDs.contains(sections[$0].id) }
        guard let first = positions.first, let last = positions.last else { return }

        let target = offset < 0 ? first + offset : last + offset
        let anchor = min(max(target, 0), sections.count - 1)
        let source = IndexSet(positions)
        // `move(fromOffsets:toOffset:)` treats the destination as the gap before that
        // element, so a downward move needs one past it.
        let destination = offset < 0 ? anchor : anchor + 1
        do {
            try WorkoutEditingService.moveSections(in: workout, from: source, to: destination, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cloneSelectedSections() {
        let targets = workout.sortedSections.filter { selectedSectionIDs.contains($0.id) }
        do {
            for section in targets {
                let copy = try WorkoutSectionCloningService.cloneSection(section, context: context)
                // A copy arrives closed: several clones at once would otherwise push the
                // originals off screen behind their own contents.
                collapsedSectionIDs.insert(copy.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// How many exercises go with the sections being deleted — sections cascade, so the
    /// confirmation says so rather than letting it be a surprise.
    private var selectedSectionExerciseCount: Int {
        workout.sortedSections
            .filter { selectedSectionIDs.contains($0.id) }
            .reduce(0) { total, section in
                switch section.sectionType {
                case .time: return total + section.sortedTimeSteps.filter { $0.stepType == .exercise }.count
                case .rep: return total + section.sortedRepExercises.count
                case .emom, .amrap: return total + section.sortedQuickExercises.count
                }
            }
    }

    private func confirmDeleteSelectedSections() {
        let targets = workout.sortedSections.filter { selectedSectionIDs.contains($0.id) }
        do {
            for section in targets {
                try WorkoutEditingService.deleteSection(section, from: workout, context: context)
            }
            selectedSectionIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleCollapseAll() {
        let collapsing = !allCollapsed
        withoutCollapseAnimation {
            if allCollapsed {
                collapsedSectionIDs.removeAll()
            } else {
                collapsedSectionIDs = Set(workout.sortedSections.map(\.id))
            }
        }
        // Collapsing shortens the page under the scroll position, which would otherwise
        // leave the view parked in the blank space the content used to occupy.
        if collapsing, let first = workout.sortedSections.first {
            scrollTargetSectionID = first.id
        }
    }

 




    /// Flat white row of actions, pinned under the hero.
    ///
    /// A ZStack, not an HStack: the centered element is its own layer so the edge
    /// buttons coming and going can never shift it, and each edge button is anchored to
    /// its own side. An HStack of equal-width labels was tried and pushed the row off
    /// screen — `.frame(maxWidth: .infinity)` on three long labels exceeds the width.
    ///
    /// Select mode takes the whole row, the same way the exercise-level one takes its:
    /// New Section and Collapse All step aside so the batch actions have room.
    @ViewBuilder
    private var sectionListControls: some View {
        let count = selectedSectionIDs.count

        ZStack {
            if inSectionSelectMode {
                HStack(spacing: 0) {
                    Spacer()
                    sectionSelectAction("chevron.up", count: count, tint: Color.appAccent, disabled: isSectionSelectionAtStart) {
                        moveSectionSelection(by: -1)
                    }
                    Spacer()
                    sectionSelectAction("chevron.down", count: count, tint: Color.appAccent, disabled: isSectionSelectionAtEnd) {
                        moveSectionSelection(by: 1)
                    }
                    Spacer()
                    sectionSelectAction("doc.on.doc", count: count, tint: Color.appAccent) {
                        cloneSelectedSections()
                    }
                    Spacer()
                    sectionSelectAction("trash", count: count, tint: Color.appDanger) {
                        showingSectionBatchDeleteConfirm = true
                    }
                    Spacer()
                }
                // Clear of the Select/Done button anchored on the left.
                .padding(.leading, 76)
                .padding(.trailing, 20)
            } else if !isLocked {
                Menu {
                    Button("Create New Section") { showingNewSectionSheet = true }
                    Button("Import Template…") { showingImportTemplateSheet = true }
                } label: {
                    Text("New Section")
                        .font(.subheadline)
                        .foregroundStyle(Color.appAccent)
                }
            }

            HStack(spacing: 10) {
                if !workout.sortedSections.isEmpty && !isLocked {
                    Button(inSectionSelectMode ? "Done" : "Select") {
                        toggleSectionSelectMode()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(Color.appAccent)
                }

                Spacer()

                if !workout.sortedSections.isEmpty && !inSectionSelectMode {
                    controlDivider
                    controlButton(allCollapsed ? "chevron.down" : "chevron.up") {
                        toggleCollapseAll()
                    }
                    controlDivider
                }
            }
            .padding(.horizontal, 20)
        }
        // Fixed, so the row's height is identical however many controls are showing.
        .frame(height: Self.controlRowHeight)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 0.5)
        }
    }

    /// Icon plus the count it would act on — same treatment the exercise-level batch
    /// actions use, so the two select modes read as one idiom.
    private func sectionSelectAction(
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
        .disabled(selectedSectionIDs.isEmpty || disabled)
    }

    /// Height of `sectionListControls`, fixed so the row is identical in both modes.
    private static let controlRowHeight: CGFloat = 44

    /// A short green rule flanking the centered menu — the cue that the label between
    /// them is its own tappable thing.
    private var controlDivider: some View {
        Rectangle()
            .fill(Color.appAccent)
            .frame(width: 1, height: 18)
    }

    private func controlButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.appAccent)
                .frame(width: 32, height: Self.controlRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            collapsedSectionIDs.insert(copy.id)
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



    /// Clones, renames the copy, then hands it to the parent to take this screen's
    /// place — backing out of the copy should reach the list, not the locked original.
    private func cloneAndEdit() {
        let trimmed = cloneWorkoutNameText.trimmingCharacters(in: .whitespaces)
        let copy = WorkoutCloningService.clone(workout, context: context)
        if !trimmed.isEmpty {
            do {
                try WorkoutEditingService.rename(copy, to: trimmed, context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        onReplaceWithClone?(copy)
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





    private func sectionIndex(_ section: WorkoutSection) -> Int {
        workout.sortedSections.firstIndex { $0.id == section.id } ?? 0
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
