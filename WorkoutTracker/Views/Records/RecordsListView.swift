import SwiftUI
import SwiftData

/// Mounts the records list only while its tab is the one on screen.
///
/// `RecordsListContent` holds a `@Query` over every set ever logged, and `@Query` re-runs
/// on every `ModelContext` change — a `TabView` keeps visited tabs mounted, so once this
/// tab had been opened, each set logged during a workout (and each CloudKit import) paid
/// for a fetch of the whole of session history and a full re-derivation of the record
/// rows, for a screen nobody was looking at.
///
/// The tradeoff is that leaving and returning rebuilds the list, so the scroll position
/// and any search text reset.
struct RecordsListView: View {
    /// Whether this is the selected tab.
    let isSelected: Bool

    var body: some View {
        if isSelected {
            RecordsListContent()
        } else {
            Color.appBackground.ignoresSafeArea()
        }
    }
}

/// Every exercise with a personal record — either a manually-saved `PersonalRecord`
/// or, absent one, the best result derived from session history (weight × reps, or
/// max hold time). Editing a derived-only row turns it into a real saved record.
private struct RecordsListContent: View {
    @Environment(\.modelContext) private var context
    // Tombstones are filtered by the store rather than fetched and then discarded in
    // Swift, so a device with a long deletion history doesn't carry it into every render.
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }, sort: \Exercise.name)
    private var allExercises: [Exercise]
    @Query(liveRecordsDescriptor()) private var allRecords: [PersonalRecord]
    /// A `@Query`, not a `context.fetch` inside the aggregation: a manual fetch is
    /// invisible to SwiftUI's dependency tracking, so a newly logged set never refreshed
    /// the derived rows — only an `Exercise`/`PersonalRecord` change could redraw them.
    /// It also means the result is fetched and cached once per change, not once per read.
    @Query(loggedSetsDescriptor()) private var allSetLogs: [SetLog]

    @State private var searchText = ""
    @State private var showingNewRecord = false
    @State private var filter = ExerciseFilter()
    /// Hidden by default, like the Exercises list — same reasoning, same controls.
    @State private var showingFilters = false
    /// Local to this screen rather than a field on `ExerciseFilter`: that type is shared
    /// with the Exercises library, where a filter for something that isn't an exercise
    /// has no meaning.
    @State private var kindFilter: RecordKindFilter = .all
    // MARK: Fix Bad Records — remove this block, `fixBadRecordsBar` and its two alerts
    // together with `PersonalRecordRepair` to take the feature out.
    //
    // Hidden rather than removed: the records it was fixing look right now, but the
    // mechanism — repair logic, undo, alerts — stays in place in case that changes.
    // Flip this back to `true` to bring the bar back; nothing else needs to change.
    private let showsFixBadRecordsBar = false
    @State private var showingFixConfirm = false
    @State private var showingUndoConfirm = false
    @State private var fixResultMessage: String?

    /// What kind of record the list is showing. EMOM and AMRAP records aren't exercises
    /// and carry none of the catalogue facets `ExerciseFilter` narrows by, so they need
    /// their own way of being singled out.
    private enum RecordKindFilter: String, CaseIterable, Identifiable {
        case all, exercises, emom, amrap
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .exercises: return "Exercises"
            case .emom: return "EMOM"
            case .amrap: return "AMRAP"
            }
        }

        /// The section kind this filter isolates, or nil when it isn't isolating one.
        var sectionKind: WorkoutSectionType? {
            switch self {
            case .emom: return .emom
            case .amrap: return .amrap
            case .all, .exercises: return nil
            }
        }

        var showsExercises: Bool { self == .all || self == .exercises }
        var showsSections: Bool { self != .exercises }
    }

    /// A record for an EMOM or AMRAP section — a name and a round count, with none of the
    /// equipment/execution-type structure an exercise record row carries.
    private struct SectionRecordRow: Identifiable {
        let record: PersonalRecord
        var id: UUID { record.id }
        var name: String { record.sectionRecordName ?? record.sectionRecordKind?.fallbackSectionName ?? "Section" }
        var kind: WorkoutSectionType? { record.sectionRecordKind }
        var summary: String { PersonalRecordFormatting.summary(record) }
    }

    /// Grouping shared with the record page — see `PersonalRecordVariants` — so the two
    /// screens can never disagree about what a variant is.
    private var variants: [RecordVariant] {
        PersonalRecordVariants.build(exercises: allExercises, records: allRecords, setLogs: allSetLogs)
    }

    /// One list row per exercise. An exercise trained on several equipment keeps all of
    /// them here — the list stays one line, and the record page's own equipment and
    /// record-type selectors reach the rest.
    private struct ExerciseRow: Identifiable {
        let exercise: Exercise
        let variants: [RecordVariant]
        var id: UUID { exercise.id }

        /// Where the record page opens: the first variant, matching the order shown.
        var leadVariant: RecordVariant? { variants.first }

        /// The line under the name: the single record's value, or — once an exercise has
        /// several — which combinations it actually holds a record for.
        ///
        /// "3 records" said how many without saying which, and with execution types the
        /// combinations multiply: barbell-explosive and barbell-slow are two entries that
        /// a bare count can't tell apart. Only *saved* records are listed; a derived best
        /// is something the app inferred from history, not a record you set.
        var summary: String {
            if let only = variants.first, variants.count == 1 { return only.summary }
            let saved = variants.filter { $0.record != nil }
            guard !saved.isEmpty else { return "\(variants.count) records" }
            return saved.map(\.sourceLabel).joined(separator: ", ")
        }

        /// Nothing to delete when every variant is derived from session history — those
        /// aren't stored records and reappear the moment the list recomputes.
        var hasSavedRecord: Bool { variants.contains { $0.record != nil } }
    }

    /// The full aggregation, unfiltered. Search is applied to the finished rows in
    /// `visibleRows` rather than inside here, so typing re-filters ~50 built structs
    /// instead of re-running the whole pipeline per keystroke.
    private var allRows: [ExerciseRow] {
        Dictionary(grouping: variants, by: { $0.exercise.id })
            .compactMap { _, group -> ExerciseRow? in
                guard let exercise = group.first?.exercise else { return nil }
                return ExerciseRow(
                    exercise: exercise,
                    variants: group.sorted { lhs, rhs in
                        if lhs.isBodyweight != rhs.isBodyweight { return lhs.isBodyweight }
                        // A resolved equipment leads an unresolved one. Sorting on
                        // `name ?? ""` alone put the empty string first, so a legacy
                        // no-equipment variant always became the row's lead — and the
                        // editor always opened on it.
                        let lhsHasEquipment = lhs.equipment != nil
                        let rhsHasEquipment = rhs.equipment != nil
                        if lhsHasEquipment != rhsHasEquipment { return lhsHasEquipment }
                        if lhs.equipment?.name != rhs.equipment?.name {
                            return (lhs.equipment?.name ?? "") < (rhs.equipment?.name ?? "")
                        }
                        if lhs.trackingMode != rhs.trackingMode {
                            return lhs.trackingMode == .repsWeight
                        }
                        // The untyped record leads, for the same reason a resolved
                        // equipment does: it is the one an exercise had before it split,
                        // and it is where the editor should open.
                        let lhsHasType = lhs.executionType != nil
                        let rhsHasType = rhs.executionType != nil
                        if lhsHasType != rhsHasType { return !lhsHasType }
                        return (lhs.executionType?.name ?? "") < (rhs.executionType?.name ?? "")
                    }
                )
            }
            .sorted { $0.exercise.name < $1.exercise.name }
    }

    private var visibleRows: [ExerciseRow] {
        guard !searchText.isEmpty || !filter.isEmpty else { return allRows }
        return allRows.filter { row in
            let matchesSearch = searchText.isEmpty
                || row.exercise.name.localizedCaseInsensitiveContains(searchText)
                || (row.exercise.label?.localizedCaseInsensitiveContains(searchText) ?? false)
            // A records list is a list of exercises, so the catalogue's own facets are
            // the ones worth narrowing by.
            return matchesSearch && filter.matches(row.exercise)
        }
    }

    /// Section records, newest-set first — the order that puts what you just beat at the
    /// top, since these have no name-ordered catalogue to sort against.
    private var allSectionRows: [SectionRecordRow] {
        allRecords
            .filter(\.isSectionRecord)
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(SectionRecordRow.init)
    }

    private var visibleSectionRows: [SectionRecordRow] {
        allSectionRows.filter { row in
            // `ExerciseFilter` is not consulted: every facet on it is a property of an
            // exercise, and a section record has none of them. Narrowing by muscle group
            // would silently empty this half of the list.
            if let kind = kindFilter.sectionKind, row.kind != kind { return false }
            return searchText.isEmpty || row.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The two row kinds in one list, section records first.
    ///
    /// One `ForEach` rather than two: the numbering, the last-row detection that drives
    /// the full-bleed styling, and the empty state all read the finished list, and a
    /// second `ForEach` would have to reproduce each of them.
    private enum ListRow: Identifiable {
        case section(SectionRecordRow)
        case exercise(ExerciseRow)

        var id: UUID {
            switch self {
            case .section(let row): return row.id
            case .exercise(let row): return row.id
            }
        }
    }

    private var listRows: [ListRow] {
        var rows: [ListRow] = []
        if kindFilter.showsSections {
            rows += visibleSectionRows.map(ListRow.section)
        }
        if kindFilter.showsExercises {
            rows += visibleRows.map(ListRow.exercise)
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageTitleBand(title: "Records") {
                    HeaderFilterControls(
                        filter: $filter,
                        showingFilters: $showingFilters,
                        // Otherwise the funnel reads as unfiltered while the list is
                        // narrowed to one section kind and the strip is closed.
                        additionalFilterActive: kindFilter != .all
                    )
                }

                // Outside `content`, so a search that matches nothing still leaves the
                // field on screen to clear or edit.
                searchField

                if showingFilters {
                    VStack(alignment: .leading, spacing: 0) {
                        kindFilterRow
                        // Only meaningful while exercise rows are on screen — every facet
                        // it offers belongs to the exercise catalogue.
                        if kindFilter.showsExercises {
                            ExerciseQuickFilterView(filter: $filter, showsFavoriteToggle: false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurface)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.appHairline)
                            .frame(height: 0.5)
                    }
                }

                content

                if showsFixBadRecordsBar {
                    fixBadRecordsBar
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingFilters)
            // The exercise chips come and go with the kind filter, so that swap needs
            // the same easing the strip's own open/close has.
            .animation(.easeInOut(duration: 0.2), value: kindFilter)
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewRecord = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            // Opens the add flow directly rather than pushing the per-exercise page
            // first — from here there's no exercise yet to show variants for, so the
            // exercise picker plus the equipment/type/mode selectors *is* the page.
            .sheet(isPresented: $showingNewRecord) {
                AddPersonalRecordSheet()
            }
            .alert("Fix bad records?", isPresented: $showingFixConfirm) {
                Button("Fix", role: .destructive) { fixBadRecords() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Merges duplicates into the real record, keeping their history. Deletes records that can't be right: empty ones, ones with no exercise, and ones set on no equipment for an exercise that only works loaded. Records that look right are left alone.")
            }
            .alert("Undo last fix?", isPresented: $showingUndoConfirm) {
                Button("Restore") { undoFix() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Brings back every record the last fix removed. If that fix wasn't run from this app since the undo existed, this restores any record deleted in the past 24 hours — including ones you deleted yourself.")
            }
            .alert("Fix Bad Records", isPresented: Binding(
                get: { fixResultMessage != nil },
                set: { if !$0 { fixResultMessage = nil } }
            )) {
                Button("OK") { fixResultMessage = nil }
            } message: {
                Text(fixResultMessage ?? "")
            }
        }
    }

    /// A repair for records that shouldn't exist — a duplicate, or the phantom
    /// "No equipment" twin of a real one.
    ///
    /// Below the list rather than a row inside it: the list renders a
    /// `ContentUnavailableView` instead when it has nothing to show, and a store whose
    /// records are all orphaned is exactly when this is needed. Quiet, because a store
    /// with nothing wrong should never draw the eye to it.
    ///
    /// Self-contained by design — see `PersonalRecordRepair`. Deleting this property, its
    /// call site above, its two `@State`s and its two alerts removes the feature whole.
    private var fixBadRecordsBar: some View {
        HStack(spacing: 0) {
            Button {
                showingFixConfirm = true
            } label: {
                Label("Fix Bad Records", systemImage: "bandage")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Color.appHairline).frame(width: 0.5, height: 20)

            // Beside Fix, not hidden behind it: everything the repair removes is a
            // tombstone rather than a real delete, and a repair you can't take back is one
            // you have to be brave to press.
            Button {
                showingUndoConfirm = true
            } label: {
                Label("Undo Last Fix", systemImage: "arrow.uturn.backward")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color.appSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
        }
    }

    private func fixBadRecords() {
        fixResultMessage = PersonalRecordRepair.run(context: context).summary
    }

    private func undoFix() {
        let restored = PersonalRecordRepair.undoLastRun(context: context)
        fixResultMessage = restored > 0
            ? "Restored \(restored) row\(restored == 1 ? "" : "s")."
            : "Nothing to restore."
    }

    /// The aggregation is read once here and handed to the rows.
    ///
    /// It used to be read from inside the `ForEach` as `rows.last?.id`, which re-ran the
    /// whole pipeline — a pass over every logged set, four dictionaries and three sorts —
    /// once per row. A 46-row list paid for it 48 times per render, so every save anywhere
    /// in the app re-ran all 48.
    @ViewBuilder
    private var content: some View {
        let rows = listRows
        let lastID = rows.last?.id

        if rows.isEmpty {
            ContentUnavailableView(
                "No Records Yet",
                systemImage: "trophy",
                description: Text(emptyStateMessage)
            )
        } else {
            List {
                // Numbered off the *visible* rows, so searching renumbers from 1 rather
                // than leaving the gaps an `allRows` position would.
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    switch row {
                    case .section(let sectionRow):
                        NavigationLink {
                            SectionRecordDetailView(record: sectionRow.record)
                        } label: {
                            sectionRowContent(sectionRow, position: index + 1)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteSectionRecord(sectionRow)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .fullBleedRow(isLast: row.id == lastID)
                    case .exercise(let exerciseRow):
                        NavigationLink {
                            editor(for: exerciseRow)
                        } label: {
                            rowContent(exerciseRow, position: index + 1)
                        }
                        .swipeActions(edge: .trailing) {
                            if exerciseRow.hasSavedRecord {
                                Button(role: .destructive) {
                                    deleteRecords(exerciseRow)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .fullBleedRow(isLast: row.id == lastID)
                    }
                }
            }
            .fullBleedList()
        }
    }

    /// Named for whichever half of the list is actually empty — "Tap + to add a record"
    /// is wrong advice when the list is filtered to EMOMs, which + cannot create.
    private var emptyStateMessage: String {
        switch kindFilter {
        case .emom, .amrap:
            return "Turn on Track record in a \(kindFilter.label) section's settings, then run it."
        case .all, .exercises:
            return "Tap + to add a record for any exercise."
        }
    }

    /// A single-select chip row, matching the muscle-category row below it in shape and
    /// tint so the two read as one filter strip.
    private var kindFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecordKindFilter.allCases) { option in
                    Button {
                        kindFilter = option
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(kindFilter == option ? Color.white : Color.appAccent)
                            .background(
                                kindFilter == option ? Color.appAccent : Color.appAccent.opacity(0.12),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    kindFilter == option ? Color.clear : Color.appAccent.opacity(0.35),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func sectionRowContent(_ row: SectionRecordRow, position: Int) -> some View {
        HStack(spacing: 12) {
            NumberBadge(number: position, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(PersonalRecordFormatting.sectionSourceLabel(name: row.summary, kind: row.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// History goes with the record, for the same reason it does for an exercise record:
    /// entries are only ever reached through `record.history`, so leaving them behind
    /// would strand them with nothing able to show or remove them.
    ///
    /// Unlike an exercise record there is nothing derived to fall back to — a deleted
    /// section record is gone until the section is run again.
    ///
    /// This is also the *only* way to unlock the sections that hold it. Track record is
    /// deliberately one-way once a record exists — a toggle that unlocked the section
    /// would undo the very thing the lock protects — so the record itself has to be the
    /// thing you remove, which is a deliberate enough act to mean it.
    private func deleteSectionRecord(_ row: SectionRecordRow) {
        for entry in row.record.history {
            SyncDeletion.delete(entry, context: context)
        }
        SyncDeletion.delete(row.record, context: context)

        // Every copy sharing the identity, in-workout and template alike — the stamp is
        // what `isLocked` reads, and leaving it behind would keep the card showing a lock
        // the editing service no longer enforces.
        if let groupID = row.record.sectionRecordGroupID {
            for section in SectionResultService.sectionsSharing(groupID: groupID, context: context) {
                section.recordLockedAt = nil
                section.markDirty()
            }
        }
        try? context.save()
    }

    /// The shared field plus the hairline it doesn't draw itself. This was a hand-rolled
    /// copy of `InlineSearchField` differing only by that line.
    private var searchField: some View {
        InlineSearchField(prompt: "Search records", text: $searchText)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
            }
    }

    private func rowContent(_ row: ExerciseRow, position: Int) -> some View {
        HStack(spacing: 12) {
            // A position, not the exercise's own symbol: those glyphs are close to
            // arbitrary and read as meaning they don't carry. `size: 34` is what
            // `IconBadge` used, so the row keeps its height and text alignment.
            NumberBadge(number: position, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.displayName)
                HStack(spacing: 4) {
                    if row.variants.count == 1, let color = row.variants.first?.settingColor {
                        Circle().fill(color.color).frame(width: 6, height: 6)
                    }
                    Text(row.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // Two lines, because a well-used exercise can hold four or five
                        // combinations and one line would cut the list off mid-name.
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Every variant is now its own section on the page itself, so there's nothing
    /// left to pick here — just which exercise.
    private func editor(for row: ExerciseRow) -> some View {
        PersonalRecordEditView(exercise: row.exercise)
    }

    /// Removes every saved record for the exercise — the way a mistyped record gets
    /// corrected, since Save only ever accepts a value that beats the standing one.
    ///
    /// History goes with it: entries are only ever reached through `record.history`, so
    /// leaving them behind would strand them with nothing able to show or remove them.
    /// A row whose bests also come from session history reappears as a derived-only row,
    /// which is right — those sets really were logged.
    private func deleteRecords(_ row: ExerciseRow) {
        for variant in row.variants {
            guard let record = variant.record else { continue }
            for entry in record.history {
                SyncDeletion.delete(entry, context: context)
            }
            SyncDeletion.delete(record, context: context)
        }
        try? context.save()
    }
}

/// Saved records that haven't been tombstoned. Filtered by the store rather than fetched
/// and then discarded in Swift, so a device with a long deletion history doesn't carry it
/// into every render.
private func liveRecordsDescriptor() -> FetchDescriptor<PersonalRecord> {
    FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.deletedAt == nil })
}

/// Every non-cancelled set ever logged, with the two relationships the aggregation reads
/// prefetched. Without the prefetch each log faults `exercise` and `equipment` one at a
/// time, which is an N+1 storm across the whole of session history.
private func loggedSetsDescriptor() -> FetchDescriptor<SetLog> {
    var descriptor = FetchDescriptor<SetLog>(predicate: #Predicate { $0.isCancelled == false })
    descriptor.relationshipKeyPathsForPrefetching = [\.exercise, \.equipment]
    return descriptor
}
