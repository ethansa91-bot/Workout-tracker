import SwiftUI
import SwiftData

/// One row in a section card's exercise list, flattened from whichever of the three
/// storage arrays that section type uses. Building this list is what lets a single card
/// render a Follow Along, Rep, EMOM or AMRAP section without branching anywhere else.
struct SessionOverviewItem: Identifiable {
    let id: UUID
    /// 1-based position within its section, shown in place of the icon.
    let position: Int
    let title: String
    /// What this exercise is currently set to, shown in rust beneath its name.
    let summary: String?
    /// `nil` only where there is genuinely nothing to configure. Every row has a gear
    /// now, including EMOM/AMRAP entries, which carry a rep count and an execution type.
    let settings: ExerciseSettingsTarget?
    var color: Color?
}

/// What a section card needs to know about its neighbours: where it sits among them and
/// how to act on it as one of several. A template has no neighbours — it is the only
/// section there is — so it passes `nil` and the card drops the position badge, Delete
/// and Save-as-template, keeping every exercise-level action.
struct SectionCardSiblings {
    let index: Int
    let count: Int
    let onReorder: (Int) -> Void
    let onDelete: () -> Void
    let onClone: () -> Void
    let onSaveAsTemplate: () -> Void
}

/// The exercise-settings panel's target plus the row it belongs to, so one `.sheet(item:)`
/// on the card can serve every row. `ExerciseSettingsTarget` is an enum over model objects
/// and carries no identity of its own.
struct IdentifiedExerciseSettings: Identifiable {
    let id: UUID
    let target: ExerciseSettingsTarget
}

/// A section's header band and its full-bleed exercise rows.
///
/// Flat and edge to edge rather than a rounded card: the header carries the section
/// name on a white band and the rows below it sit on plain
/// `appSurface`, matching the tab roots. Without a title — the template editor, where
/// the page header names the section — the band is dropped and only the rows go
/// full-bleed.
///
/// Shared by `SessionRecapView` (many cards, one per section) and `SectionDetailView`
/// (exactly one, for a standalone template), so an improvement to the exercise rows
/// lands on both. Everything here is scoped to the single `section` it is given; the
/// only cross-section concerns live behind `siblings`.
struct SectionCardView: View {
    @Bindable var section: WorkoutSection
    /// Collapsed state is owned by the caller: the recap screen collapses every card at
    /// once, and needs to read back whether they all are.
    @Binding var isCollapsed: Bool
    /// Section-level select mode on the parent screen. While it's on the band shows a
    /// tick and a tap selects the section instead of collapsing it, so a tap can never
    /// mean two things at once.
    var inSectionSelectMode: Bool = false
    var isSectionSelected: Bool = false
    var onToggleSectionSelected: () -> Void = {}
    /// `nil` for a standalone section — see `SectionCardSiblings`.
    var siblings: SectionCardSiblings?
    /// Set when a bulk collapse is in flight, so N cards don't each animate their height
    /// against a reflowing scroll stack.
    var suppressCollapseAnimation: Bool = false
    /// Which half of the card to render.
    ///
    /// Sticky headers need the gray band and the exercise rows handed to a `Section`'s
    /// `header:` and content slots separately, so the two are rendered by two instances
    /// rather than one. They share `isCollapsed` through its binding; everything else
    /// each half owns is local to it (select mode and the exercise panels live in the
    /// body, the section panel and the edit sheet in the header), so nothing is lost
    /// by splitting.
    enum Part {
        /// Header band, plus the Select/Add row that pins with it.
        case header
        /// The exercise rows.
        case body
        /// Both, stacked. No caller left: both screens split the card so their action
        /// row can pin. Kept as the default so a new caller that doesn't care about
        /// pinning gets a working card from the shortest possible argument list.
        case whole
    }

    var part: Part = .whole
    /// Off where the screen's own header already carries the section's name, summary and
    /// settings — the card's header row would then be an empty strip.
    var showsHeader: Bool = true
    /// Off where there is only one section on screen, so collapsing it hides the entire
    /// page's content for no benefit.
    var showsCollapseControl: Bool = true
    /// Off when the screen around the card already names the section — a standalone
    /// section's page header carries the name and description, so repeating them in the
    /// card directly beneath reads as a stutter. The settings summary stays either way:
    /// it's the one line the header doesn't show.
    var showsTitle: Bool = true
    var onError: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context

    // Bindings, not `@State`: with `part` splitting the card into two instances, any
    // flag both halves touch would otherwise fork into two independent copies. Select
    // mode is the clearest case — the Select button lives in the header and the row
    // checkboxes in the body, so `@State` left the body permanently out of select mode.
    // The batch-delete pair goes the same way: the trash icon is in the header, the
    // per-row delete in the body, and one alert reads both.
    @Binding var inSelectMode: Bool
    @Binding var selectedItemIDs: Set<UUID>
    @Binding var showingBatchDeleteConfirm: Bool
    @Binding var pendingDeleteItemID: UUID?
    @State private var showingSectionSettings = false
    @State private var showingDescription = false
    @State private var settingsItemID: UUID?
    @State private var positionPickerItemID: UUID?
    @State private var showingSectionPositionPicker = false
    @State private var positionPickerValue = 1
    @State private var showingAddExercises = false
    @State private var showingEditSheet = false
    /// The exercise whose page is open, if any. Held on the card rather than in the gear
    /// settings panel: a sheet presented from inside another sheet dies with it.
    @State private var exerciseBeingEdited: Exercise?
    @State private var nameText = ""
    @State private var descriptionText = ""

    private var isLocked: Bool { section.isLocked }

    /// Whether this section's record identity already has a template, in which case saving
    /// another would be a second live section feeding one record — see
    /// `WorkoutSectionCloningService.saveAsTemplate`, which refuses it.
    private var hasRecordTemplate: Bool {
        guard section.tracksRecord, let groupID = section.recordGroupID else { return false }
        return SectionResultService.sectionsSharing(groupID: groupID, context: context)
            .contains { $0.isTemplate && $0.id != section.id }
    }
    private var showsActions: Bool { !isLocked && !inSectionSelectMode }

    /// Collapsing is a reading affordance, not an edit — a locked workout is exactly
    /// where it earns its keep, since those are the ones with a full history behind
    /// them and the most sections to scroll past. It goes only while selecting, when a
    /// tap on the band means "select this".
    private var showsChevron: Bool { showsCollapseControl && !inSectionSelectMode }

    // The band is light, so the header keeps the ink palette either way — no inversion,
    // and the template editor (no band, cream ground) reads identically.
    private var headerTitleColor: Color { Color.appInk }
    private var headerIconColor: Color { Color.appInkMuted }
    private var headerDetailColor: Color { Color.appRust }

    var body: some View {
        let items = overviewItems

        // Stack spacing is 0 and every element owns its padding, so nothing above the
        // divider depends on `isCollapsed` — the header subtree is byte-identical in
        // both states and cannot shift when the section opens or closes.
        VStack(alignment: .leading, spacing: 0) {
            if part != .body {
                if showsHeader {
                    header
                }
                // Pinned with the band, so a section's actions stay reachable while its
                // exercises scroll under them. Hidden when collapsed — a closed section
                // offering "Add Exercise" reads as a bug.
                if showsActions, !isCollapsed {
                    addExerciseRow
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.appSurface)
                    if !items.isEmpty {
                        Rectangle()
                            .fill(Color.appHairline)
                            .frame(height: 0.5)
                            .padding(.leading, 16)
                    }
                }
            }

            if part != .header {
                // Always mounted, collapsed by height rather than by `if`. Inserting and
                // removing the subtree makes SwiftUI drop it in one frame instead of
                // animating, which is what made the section blink out; animating a real
                // height gives a continuous change instead.
                //
                // No opacity fade here on purpose: fading makes the rows dissolve in
                // place while they're still drawn over the header. Letting the clip
                // alone hide them means they slide up and disappear behind the header
                // edge.
                collapsibleBody(items: items)
                    .frame(maxHeight: isCollapsed ? 0 : .infinity, alignment: .top)
                    .clipped()
            }
        }
        // Implicit, so it fires on any change to this section's state no matter who
        // made it — which is why a bulk change has to switch it off rather than just
        // omitting `withAnimation` at the call site.
        .animation(suppressCollapseAnimation ? nil : .easeInOut(duration: 0.25), value: isCollapsed)
        .sheet(item: Binding(
            get: { openExerciseSettings },
            set: { if $0 == nil { settingsItemID = nil } }
        )) { open in
            ExerciseSettingsPanel(
                target: open.target,
                context: context,
                onClone: {
                    settingsItemID = nil
                    cloneItems([open.id])
                },
                onDelete: {
                    settingsItemID = nil
                    pendingDeleteItemID = open.id
                    showingBatchDeleteConfirm = true
                },
                onEditExercise: editExerciseAction(for: open.target),
                onAddRest: addRestAction(for: open.target)
            )
        }
        .sheet(isPresented: $showingAddExercises) {
            MultiExercisePickerView(existingExerciseIDs: existingExerciseIDs) { exercises in
                addExercises(exercises)
            }
        }
        .sheet(isPresented: $showingEditSheet) { editSheet }
        .sheet(item: $exerciseBeingEdited) { exercise in
            ExerciseDetailView(exercise: exercise, isPresentedAsSheet: true)
        }
        .alert(
            "Delete \(pendingDeleteCount) exercise\(pendingDeleteCount == 1 ? "" : "s")?",
            isPresented: $showingBatchDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { confirmBatchDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteItemID = nil }
        }
    }

    // MARK: - Header

    /// Name + pencil on row 1 (alongside the section's own actions), description on
    /// row 2, and the timing settings the gear panel controls summarised on row 3 —
    /// so what Rounds/Autostart/Repeat are currently set to is readable without
    /// opening anything.
    /// Carries the section name on its own white band. Without a title (the template
    /// editor, where the green page header names the section) there's nothing to band,
    /// so it stays on the plain ground.
    @ViewBuilder
    private var header: some View {
        headerContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                guard inSectionSelectMode else { return }
                onToggleSectionSelected()
            }
            .background(showsTitle ? Color.appSurface : Color.clear)
    }

    @ViewBuilder
    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // Unreachable with `showsHeader: false`, which the only `showsTitle:
                // false` caller also passes — the template editor's green band carries
                // the summary itself.
                if showsTitle {
                HStack(spacing: 8) {
                    if inSectionSelectMode {
                        Image(systemName: isSectionSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSectionSelected ? Color.appAccent : Color.appInkMuted)
                    }

                    // Only meaningful with neighbours to move among — a standalone
                    // section is always "1 of 1".
                    if let siblings, showsActions, siblings.count > 1 {
                        Button {
                            positionPickerValue = siblings.index + 1
                            showingSectionPositionPicker = true
                        } label: {
                            NumberBadge(number: siblings.index + 1, tint: Color.appInkMuted)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingSectionPositionPicker) {
                            sectionPositionPicker(siblings: siblings)
                        }
                    } else if let siblings {
                        NumberBadge(number: siblings.index + 1, tint: Color.appInkMuted)
                    }

                    Text(sectionTitle)
                        .font(.headline)
                        .foregroundStyle(headerTitleColor)
                        .lineLimit(1)

                    if showsActions {
                        Button {
                            nameText = section.name ?? ""
                            descriptionText = section.sectionDescription ?? ""
                            showingEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(headerIconColor)
                    }

                    // A description is usually a paragraph — too long for the header, so
                    // it moves behind an icon that only appears when there is one.
                    if let description = section.sectionDescription, !description.isEmpty {
                        Button {
                            showingDescription = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(headerIconColor)
                        .popover(isPresented: $showingDescription) {
                            descriptionPopover(description)
                        }
                    }

                    // Kind and count ride with the name rather than heading the settings
                    // line below, which leaves that line short enough to fit on one row.
                    // Lowest layout priority, so this is what truncates when a long name
                    // and the icons compete for the row.
                    Text(sectionKindSummary(section))
                        .font(.caption)
                        .foregroundStyle(headerDetailColor)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                }

                Spacer()

                // While rearranging, the only actions available are dragging sections and
                // adding a new one — Clone/Delete/Settings hide entirely so a stray tap
                // can't do anything else mid-reorder.
                // Save-as-template is a sibling-level action: a template can't be saved
                // as another template. It survives the lock — copying a section out
                // changes nothing about the workout it came from — but not a record
                // identity that already has a template, which is the one case where the
                // copy would be a second section feeding one record.
                if let siblings, !inSectionSelectMode, !hasRecordTemplate {
                    Button {
                        siblings.onSaveAsTemplate()
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(headerIconColor)
                }

                if showsActions {
                    // The sheet is still attached to the gear rather than to the card:
                    // it no longer *has* to be — a sheet has no anchor, where a popover
                    // pointed at whichever view carried the modifier — but the button and
                    // what it opens read better together than a modifier hung two levels
                    // up from the only thing that sets its flag.
                    Button {
                        showingSectionSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(headerDetailColor)
                    .sheet(isPresented: $showingSectionSettings) {
                        SectionSettingsPanel(
                            section: section,
                            context: context,
                            onError: onError,
                            // Clone and Delete only exist among siblings. The panel
                            // hides each action whose handler is nil.
                            onClone: siblings.map { s in {
                                showingSectionSettings = false
                                s.onClone()
                            } },
                            onDelete: siblings.map { s in {
                                showingSectionSettings = false
                                s.onDelete()
                            } }
                        )
                    }
                }

                // Last in the row and gated separately, so its position never shifts as
                // the other icons come and go.
                if showsChevron {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(headerIconColor)
                }
            }

            // Kind and count now sit beside the name, so this line carries only what the
            // section is set to — short enough to stay on one row.
            if showsTitle {
                Text(sectionSettingsSummary(section))
                    .font(.caption)
                    .foregroundStyle(headerDetailColor)
                    .lineLimit(1)
            }
        }
    }

    /// The section's description, behind the header's info button — the same glass
    /// treatment the position wheel and settings panel use.
    private func descriptionPopover(_ description: String) -> some View {
        ScrollView {
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.appInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(width: 260, height: 180)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }

    private var sectionTitle: String {
        if let name = section.name, !name.isEmpty { return name }
        return section.sectionType.fallbackSectionName
    }

    // MARK: - Body

    /// Just the exercise rows — the Select/Add row above them belongs to the header half
    /// so it pins with the band.
    private func collapsibleBody(items: [SessionOverviewItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rows sit flush against each other rather than in the outer stack's 12pt
            // spacing: a highlighted row's gray has to fill its whole slot, and any gap
            // above it reads as empty space stacked on top of the highlight.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    overviewItemRow(
                        item,
                        isLast: item.id == items.last?.id,
                        itemCount: items.count
                    )
                }
            }
        }
    }

    /// Add Exercise normally; in select mode the same row turns into the batch
    /// actions for whatever is ticked, with Select/Done anchoring the left edge.
    ///
    /// A ZStack so Add Exercise centres on the row rather than on the space left over
    /// after Select — flanking Spacers put it noticeably right of centre.
    @ViewBuilder
    private var addExerciseRow: some View {
        let count = selectedItemIDs.count

        ZStack {
            if inSelectMode {
                // Four actions plus Select/Done doesn't fit with word labels on a narrow
                // phone, so each is an icon with its count beside it.
                HStack(spacing: 0) {
                    Spacer()
                    selectAction("chevron.up", count: count, tint: Color.appAccent, disabled: isSelectionAtStart) {
                        moveSelection(by: -1)
                    }
                    Spacer()
                    selectAction("chevron.down", count: count, tint: Color.appAccent, disabled: isSelectionAtEnd) {
                        moveSelection(by: 1)
                    }
                    Spacer()
                    selectAction("doc.on.doc", count: count, tint: Color.appAccent) {
                        cloneItems(selectedItemIDs)
                    }
                    Spacer()
                    selectAction("trash", count: count, tint: Color.appDanger) {
                        showingBatchDeleteConfirm = true
                    }
                    Spacer()
                }
                // Clear of the Select/Done button anchored on the left.
                .padding(.leading, 60)
            } else {
                Button {
                    showingAddExercises = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
            }

            HStack {
                Button(inSelectMode ? "Done" : "Select") {
                    toggleSelectMode()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Color.appAccent)

                Spacer()
            }
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

    private func toggleSelectMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            inSelectMode.toggle()
            // Entering or leaving always starts from a clean slate.
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

    /// Name over a rust line of whatever that exercise is currently set to, with its
    /// own gear — the same shape the section header above it uses, one level down.
    private func overviewItemRow(
        _ item: SessionOverviewItem,
        isLast: Bool,
        itemCount: Int
    ) -> some View {
        let selecting = showsActions && inSelectMode
        let isSelected = selectedItemIDs.contains(item.id)
        // Whatever the row is currently the subject of — ticked, or holding an open
        // panel — gets the same light-gray backing so it's obvious which row an
        // action will apply to.
        let isActive = isSelected
            || settingsItemID == item.id
            || positionPickerItemID == item.id

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.appAccent : Color.appInkMuted)
                }

                if showsActions, !selecting, itemCount > 1 {
                    Button {
                        positionPickerValue = item.position
                        positionPickerItemID = item.id
                    } label: {
                        NumberBadge(number: item.position, tint: item.color ?? .accentColor)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: positionPickerBinding(for: item.id)) {
                        positionPicker(item: item, count: itemCount)
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
                if showsActions, !selecting, let settings = item.settings {
                    Button {
                        settingsItemID = item.id
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.appHighlightGray : Color.appSurface)
            .contentShape(Rectangle())
            .onTapGesture {
                guard selecting else { return }
                toggleSelected(item.id)
            }

            if !isLast {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }

    // MARK: - Items

    private var overviewItems: [SessionOverviewItem] {
        switch section.sectionType {
        case .time:
            // Get Ready is edited from the section's gear instead of appearing here —
            // it's still a real step the runner plays, just not one of the exercises.
            let steps = section.sortedTimeSteps.filter { $0.stepType != .getReady }
            return steps.enumerated().map { index, step in
                SessionOverviewItem(
                    id: step.id,
                    position: index + 1,
                    title: step.displayTitle,
                    summary: exerciseSettingsSummary(.timeStep(step)),
                    settings: .timeStep(step),
                    // `resolvedColor` already answers this: green for an exercise
                    // that was never coloured, gray for Rest/Get Ready.
                    color: step.resolvedColor.color
                )
            }
        case .rep:
            return section.sortedRepExercises.enumerated().map { index, entry in
                SessionOverviewItem(
                    id: entry.id,
                    position: index + 1,
                    title: entry.displayTitle,
                    summary: exerciseSettingsSummary(.repEntry(entry)),
                    settings: .repEntry(entry)
                )
            }
        case .emom, .amrap:
            return section.sortedQuickExercises.enumerated().map { index, entry in
                SessionOverviewItem(
                    id: entry.id,
                    position: index + 1,
                    title: entry.displayTitle,
                    summary: exerciseSettingsSummary(.quickEntry(entry)),
                    settings: .quickEntry(entry)
                )
            }
        }
    }



    /// The exercise behind a row, or nil for a Rest or Get Ready step — which have none,
    /// so the button is hidden rather than shown dead.
    ///
    /// Closes the panel before presenting: the sheet would otherwise be a child of a
    /// view that is about to disappear, and go with it.
    private func editExerciseAction(for target: ExerciseSettingsTarget) -> (() -> Void)? {
        let exercise: Exercise?
        switch target {
        case .timeStep(let step): exercise = step.stepType == .exercise ? step.exercise : nil
        case .repEntry(let entry): exercise = entry.exercise
        case .quickEntry(let entry): exercise = entry.exercise
        }
        guard let exercise else { return nil }
        return {
            settingsItemID = nil
            exerciseBeingEdited = exercise
        }
    }

    /// Only follow-along steps can gain a rest after them — every other row passes nil,
    /// which is what hides the button rather than showing a dead one.
    private func addRestAction(for target: ExerciseSettingsTarget) -> (() -> Void)? {
        guard case .timeStep(let step) = target, step.stepType == .exercise else { return nil }
        return {
            settingsItemID = nil
            addRest(after: step)
        }
    }

    private func addRest(after step: TimeSectionStep) {
        do {
            _ = try WorkoutEditingService.addRestStep(after: step, durationSeconds: 30, context: context)
        } catch {
            onError(error.localizedDescription)
        }
    }

    // MARK: - Exercises

    private var existingExerciseIDs: Set<UUID> {
        switch section.sectionType {
        case .time: return Set(section.sortedTimeSteps.compactMap { $0.exercise?.id })
        case .rep: return Set(section.sortedRepExercises.compactMap { $0.exercise?.id })
        case .emom, .amrap: return Set(section.sortedQuickExercises.compactMap { $0.exercise?.id })
        }
    }

    /// Appends with the same per-type defaults each section type expects, so an exercise
    /// added here is indistinguishable from one added anywhere else.
    private func addExercises(_ exercises: [Exercise]) {
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
                onError(error.localizedDescription)
                break
            }
        }
    }

    // MARK: - Per-row and batch actions

    private func cloneItems(_ ids: Set<UUID>) {
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
            onError(error.localizedDescription)
        }
    }

    private func deleteItems(_ ids: Set<UUID>) {
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
            onError(error.localizedDescription)
        }
    }

    /// How many rows the pending confirm would remove — one when it came from a row's
    /// own gear, otherwise everything ticked in select mode.
    private var pendingDeleteCount: Int {
        pendingDeleteItemID != nil ? 1 : selectedItemIDs.count
    }

    private func confirmBatchDelete() {
        if let single = pendingDeleteItemID {
            deleteItems([single])
        } else {
            deleteItems(selectedItemIDs)
            selectedItemIDs.removeAll()
        }
        pendingDeleteItemID = nil
    }

    // MARK: - Moving rows
    //
    // Display rows are not the model array. A `.time` section hides its Get Ready step
    // from the list but still keeps it at index 0, so every move has to be expressed in
    // model indices — moving by display index would push Get Ready out of first place
    // and the section would start mid-exercise.

    /// The section's rows in model order, with the ones the list never shows removed.
    private var displayRowIDs: [UUID] {
        switch section.sectionType {
        case .time: return section.sortedTimeSteps.filter { $0.stepType != .getReady }.map(\.id)
        case .rep: return section.sortedRepExercises.map(\.id)
        case .emom, .amrap: return section.sortedQuickExercises.map(\.id)
        }
    }

    /// Every row in model order, Get Ready included.
    private var modelRowIDs: [UUID] {
        switch section.sectionType {
        case .time: return section.sortedTimeSteps.map(\.id)
        case .rep: return section.sortedRepExercises.map(\.id)
        case .emom, .amrap: return section.sortedQuickExercises.map(\.id)
        }
    }

    private func applyMove(from source: IndexSet, to destination: Int) {
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
            onError(error.localizedDescription)
        }
    }

    /// Moves `ids` (kept in their existing relative order) so they land starting at
    /// `displayPosition`, a 1-based index into the *visible* rows.
    private func move(ids: Set<UUID>, toDisplayPosition displayPosition: Int) {
        let display = displayRowIDs
        let model = modelRowIDs
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

        applyMove(from: sourceIndices, to: destination)
    }

    /// Shifts the selected rows one slot, as a block. Non-contiguous picks gather
    /// together at the destination — `move(ids:toDisplayPosition:)` preserves the
    /// selection's relative order, so the block keeps the order shown on screen.
    ///
    /// The selection deliberately survives, so the same rows can be walked up or down
    /// the list with repeated taps instead of being re-picked each time.
    private func moveSelection(by offset: Int) {
        let display = displayRowIDs
        let positions = display.indices.filter { selectedItemIDs.contains(display[$0]) }
        guard let first = positions.first, let last = positions.last else { return }

        // Anchor on whichever end leads the move, so a block travelling down lands past
        // the row it displaces rather than on top of it.
        let target = offset < 0 ? first + offset : last + offset
        let clamped = min(max(target, 0), display.count - 1)
        move(ids: selectedItemIDs, toDisplayPosition: clamped + 1)
    }

    /// Nothing above the selection to swap with — the Up button has no work to do.
    private var isSelectionAtStart: Bool {
        guard let firstID = displayRowIDs.first else { return true }
        return selectedItemIDs.contains(firstID)
    }

    private var isSelectionAtEnd: Bool {
        guard let lastID = displayRowIDs.last else { return true }
        return selectedItemIDs.contains(lastID)
    }

    // MARK: - Pickers and sheets

    private func positionPickerBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { positionPickerItemID == id },
            set: { if !$0 && positionPickerItemID == id { positionPickerItemID = nil } }
        )
    }

    /// The open row's settings, if any — the card's one exercise panel resolves its
    /// target from the id rather than each row carrying its own presentation.
    ///
    /// As a popover this had to hang off each row's gear, because a popover points at the
    /// view carrying the modifier and `.popover(item:)` would have tried to present on
    /// every row on screen at once. A sheet has no anchor, so one is enough.
    private var openExerciseSettings: IdentifiedExerciseSettings? {
        guard let id = settingsItemID,
              let item = overviewItems.first(where: { $0.id == id }),
              let settings = item.settings
        else { return nil }
        return IdentifiedExerciseSettings(id: id, target: settings)
    }

    /// Native wheel of every position in the section, current one preselected — pick a
    /// different number and the exercise moves there.
    private func positionPicker(item: SessionOverviewItem, count: Int) -> some View {
        positionWheel(count: count) {
            if positionPickerValue != item.position {
                move(ids: [item.id], toDisplayPosition: positionPickerValue)
            }
            positionPickerItemID = nil
        }
    }

    /// Same wheel as an exercise's, routed through the caller's reorder handler instead.
    private func sectionPositionPicker(siblings: SectionCardSiblings) -> some View {
        positionWheel(count: siblings.count) {
            if positionPickerValue != siblings.index + 1 {
                siblings.onReorder(positionPickerValue)
            }
            showingSectionPositionPicker = false
        }
    }

    /// The wheel both pickers share — they differ only in what Save does.
    private func positionWheel(count: Int, onSave: @escaping () -> Void) -> some View {
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
            Button(action: onSave) {
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

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Section name", text: $nameText)
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
            onError(error.localizedDescription)
        }
    }
}
