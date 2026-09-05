import SwiftUI
import SwiftData

/// One exercise's personal records: every equipment/execution-type/tracking-mode
/// combination it has a record for (saved or just logged), each its own collapsible
/// section with its own history — rather than the equipment/type/mode selectors that
/// used to sit fixed at the top of this page, deciding which single record you were
/// looking at.
///
/// The highest real, comparable weight this exercise has ever moved — separately for
/// reps and for max time, converted to one unit so different equipment can be compared
/// at all — leads the list, highlighted rather than restated. Creating a genuinely new
/// combination moved behind "Add Record"; see `AddPersonalRecordSheet`, which is also
/// what the Records list's own "+" opens directly.
struct PersonalRecordEditView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var context

    @State private var variants: [RecordVariant] = []
    /// Which variant's history is open — at most one at a time, the same idiom used
    /// throughout the app for a tap-to-expand row (see `EquipmentDetailView.optionRow`).
    @State private var expandedHistoryKey: RecordVariantKey?
    /// The variant the pencil opened a corrector for — a settings-style bottom sheet
    /// (`RecordEditPopup`) rather than an inline row, the same pattern
    /// `SectionSettingsPanel` uses for a section's own settings.
    @State private var editingVariant: RecordVariant?
    @State private var showingAddRecord = false
    /// A past history entry the trash icon was tapped on, awaiting the confirm alert —
    /// not `role: .destructive` on the icon itself, since that plays no removal
    /// animation here the way a destructive swipe action would (see
    /// `SessionHistoryListView`'s own version of this pattern); the role belongs on the
    /// alert's own confirm button instead.
    @State private var pendingDeleteEntry: PersonalRecordEntry?
    /// The variant whose *standing* value the trash icon was tapped on — distinct from
    /// `pendingDeleteEntry` since there's no `PersonalRecordEntry` to point at for the
    /// current value, only the record itself. See `deleteCurrentValue`.
    @State private var pendingDeleteCurrent: RecordVariant?

    var body: some View {
        Group {
            if variants.isEmpty {
                ContentUnavailableView(
                    "No Records Yet",
                    systemImage: "trophy",
                    description: Text("Add Record below to set one.")
                )
            } else {
                List {
                    ForEach(sortedVariants) { variant in
                        Group {
                            headerRow(variant)
                            if expandedHistoryKey == variant.key {
                                historyRows(for: variant)
                            }
                            // A boundary after every variant's own content, whatever that
                            // content happens to be — collapsed header or an open history.
                            // `headerRow`/`historyRows` only ever decide separators
                            // *within* a variant (header vs. its own expanded history);
                            // without this, two collapsed variants sat back to back with
                            // no line between them at all.
                            variantDivider(isLast: variant.id == sortedVariants.last?.id)
                        }
                    }
                }
                .fullBleedList()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(title: exercise.displayName)
        }
        .safeAreaInset(edge: .bottom) {
            // Hidden while the edit popup is up: it opens at a fitted, partial height
            // (`SettingsPanelSheet`) that leaves the sheet's translucent material over
            // whatever's behind it, and a second call-to-action floating under that read
            // as two competing bottom actions.
            if editingVariant == nil {
                addRecordButton
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddRecord) {
            AddPersonalRecordSheet(exercise: exercise, onSaved: refresh)
        }
        .sheet(item: $editingVariant) { variant in
            RecordEditPopup(exercise: exercise, variant: variant, context: context) { _ in
                refresh()
                editingVariant = nil
            }
        }
        .alert("Delete this entry?", isPresented: Binding(
            get: { pendingDeleteEntry != nil },
            set: { if !$0 { pendingDeleteEntry = nil } }
        )) {
            Button("Delete", role: .destructive) { deletePendingEntry() }
            Button("Cancel", role: .cancel) { pendingDeleteEntry = nil }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Delete this record?", isPresented: Binding(
            get: { pendingDeleteCurrent != nil },
            set: { if !$0 { pendingDeleteCurrent = nil } }
        )) {
            Button("Delete", role: .destructive) { deletePendingCurrent() }
            Button("Cancel", role: .cancel) { pendingDeleteCurrent = nil }
        } message: {
            Text("The next most recent value on file takes its place. If there isn't one, this removes the record entirely.")
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        variants = PersonalRecordVariants.variants(for: exercise, context: context)
    }

    private func deletePendingEntry() {
        guard let entry = pendingDeleteEntry else { return }
        SyncDeletion.delete(entry, context: context)
        try? context.save()
        pendingDeleteEntry = nil
        refresh()
    }

    private func deletePendingCurrent() {
        guard let variant = pendingDeleteCurrent else { return }
        pendingDeleteCurrent = nil
        deleteCurrentValue(for: variant)
    }

    /// Deletes the record's own standing value in favor of whatever it most recently
    /// superseded — the mirror image of `PersonalRecordQueries.setRecord`, which files
    /// the current value into a fresh history entry every time a *new* one is saved.
    /// With no history to fall back to, there's nothing left to promote, so this is the
    /// same as deleting the whole record.
    private func deleteCurrentValue(for variant: RecordVariant) {
        guard let record = variant.record else { return }
        guard let mostRecent = record.history.first else {
            deleteRecord(for: variant)
            return
        }
        record.weight = mostRecent.weight
        record.reps = mostRecent.reps
        record.holdSeconds = mostRecent.holdSeconds
        record.weightUnit = mostRecent.weightUnit
        // The record's own `updatedAt` doubles as its "when this was achieved" stamp —
        // `setRecord` establishes that convention itself, stamping a fresh entry's
        // `achievedAt` from the record's `updatedAt` at the moment it's superseded.
        // Reversing that has to restore the same stamp, or this would read as achieved
        // just now instead of whenever it actually was.
        record.updatedAt = mostRecent.achievedAt
        SyncDeletion.delete(mostRecent, context: context)
        try? context.save()
        refresh()
    }

    private var addRecordButton: some View {
        Button {
            showingAddRecord = true
        } label: {
            Label("Add Record", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .padding()
    }

    // MARK: - Ordering and the absolute record

    /// The absolute-record variant(s) lead, each still in its own natural place among
    /// the rest — not duplicated, just promoted and, in the row itself, highlighted.
    private var sortedVariants: [RecordVariant] {
        let absoluteIDs = Set(absoluteRecordVariants.map(\.id))
        guard !absoluteIDs.isEmpty else { return variants }
        let promoted = variants.filter { absoluteIDs.contains($0.id) }
        let rest = variants.filter { !absoluteIDs.contains($0.id) }
        return promoted + rest
    }

    /// The single highest real weight this exercise has ever moved, separately for
    /// reps and for max time — unit-converted so a kg record and an lb record can be
    /// compared at all. Bodyweight, option-based equipment and Follow Along records are
    /// excluded by `RecordVariant.absoluteComparisonWeightInKg` itself: "options are
    /// separate, not used for absolute records," bodyweight has no load to compare, and
    /// a carried Follow Along load isn't a performance to rank the same way a rep or
    /// hold record is.
    private var absoluteRecordVariants: [RecordVariant] {
        [RepExerciseTrackingMode.repsWeight, .maxHoldTime].compactMap { mode in
            variants
                .filter { $0.trackingMode == mode }
                .compactMap { variant in variant.absoluteComparisonWeightInKg.map { (variant, $0) } }
                .max { $0.1 < $1.1 }
                .map(\.0)
        }
    }

    // MARK: - Rows

    private func headerRow(_ variant: RecordVariant) -> some View {
        let isAbsolute = absoluteRecordVariants.contains { $0.id == variant.id }
        let isHistoryExpanded = expandedHistoryKey == variant.key

        return HStack(spacing: 8) {
            if isAbsolute {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Color.appAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.headerLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appInk)
                HStack(spacing: 4) {
                    if let color = variant.settingColor {
                        Circle().fill(color.color).frame(width: 8, height: 8)
                    }
                    Text(variant.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.appRust)
                }
            }
            Spacer(minLength: 8)
            Button {
                editingVariant = variant
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.appAccent)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isHistoryExpanded ? 90 : 0))
        }
        .padding(.leading, 16)
        .padding(.vertical, 12)
        // No trailing padding: `fullBleedRow` already reserves the standard 16pt gutter
        // on that edge (for what's normally a `NavigationLink` chevron), and its
        // separator lines up with that same edge — leaving content flush to its own
        // trailing edge is what puts this row's own chevron on that exact line instead
        // of stopping another 16pt short of it.
        .contentShape(Rectangle())
        // The tappable area is the whole row except the pencil, which is its own
        // button and takes the tap first within its own bounds.
        .onTapGesture {
            withAnimation { expandedHistoryKey = isHistoryExpanded ? nil : variant.key }
        }
        .background(Color.appSurface)
        .fullBleedRow(isLast: !isHistoryExpanded)
        .swipeActions(edge: .trailing) {
            // Only offered once there's an actual `PersonalRecord` to remove — a
            // derived-only variant has nothing behind it but the sets themselves, and
            // deleting those isn't what a swipe on the Records screen should ever do.
            if variant.record != nil {
                Button(role: .destructive) {
                    deleteRecord(for: variant)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// Removes the variant's saved record entirely — its whole history along with it, not
    /// just the standing value — and refreshes. A variant still backed by logged sets
    /// reappears as a derived one rather than vanishing outright; one with nothing else
    /// behind it disappears, and the page falls back to its empty state once none are left.
    private func deleteRecord(for variant: RecordVariant) {
        guard let record = variant.record else { return }
        for entry in record.history {
            SyncDeletion.delete(entry, context: context)
        }
        SyncDeletion.delete(record, context: context)
        try? context.save()
        if expandedHistoryKey == variant.key { expandedHistoryKey = nil }
        refresh()
    }

    /// A separator-only row, with no content of its own — see the call site's comment
    /// for why this is the one thing that reliably marks the end of a variant.
    private func variantDivider(isLast: Bool) -> some View {
        Color.clear
            .frame(height: 0)
            .fullBleedRow(isLast: isLast)
    }

    /// The record's progression, newest first — the standing record, then every value
    /// it superseded. Read-only below the top row: history is a log of what actually
    /// happened rather than something to revise.
    @ViewBuilder
    private func historyRows(for variant: RecordVariant) -> some View {
        if let record = variant.record {
            historyRow(
                text: PersonalRecordFormatting.summary(record),
                date: record.updatedAt,
                isCurrent: true,
                isLast: record.history.isEmpty,
                onDelete: { pendingDeleteCurrent = variant }
            )
            ForEach(record.history) { entry in
                historyRow(
                    text: PersonalRecordFormatting.summary(entry),
                    date: entry.achievedAt,
                    isCurrent: false,
                    isLast: entry.id == record.history.last?.id,
                    onDelete: { pendingDeleteEntry = entry }
                )
            }
        } else {
            // No explicit record — just the best of what's actually been logged — but
            // that's not "unsaved" any more than a record filed automatically mid-workout
            // is: doing the workout is the main way a record is set at all, so this reads
            // as the same kind of row as every other, just with no history behind it yet.
            historyRow(text: variant.summary, date: nil, isCurrent: true, isLast: true)
        }
    }

    /// `onDelete` is offered for the current value and every past entry alike — a wrong
    /// value is a wrong value whichever one it is — but never for the derived-only
    /// fallback row, which has no `PersonalRecord`/`PersonalRecordEntry` behind it at
    /// all, only the logged sets themselves.
    private func historyRow(text: String, date: Date?, isCurrent: Bool, isLast: Bool, onDelete: (() -> Void)? = nil) -> some View {
        HStack {
            Text(text)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.appInk)
            Spacer()
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.appDanger)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .fullBleedRow(isLast: isLast)
    }
}

/// The pencil's correction popup: a bottom sheet fitted to its own content, the same
/// `SettingsPanelSheet` chrome `SectionSettingsPanel` uses — a settings-style panel
/// rather than the row growing in place, which is what this replaced.
private struct RecordEditPopup: View {
    let exercise: Exercise
    let variant: RecordVariant
    let context: ModelContext
    let onSaved: (PersonalRecord) -> Void

    /// Measured by `SettingsPanelSheet` so the sheet opens exactly as tall as this needs.
    @State private var contentSize: CGSize = .zero

    var body: some View {
        SettingsPanelSheet(contentSize: $contentSize) {
            VStack(alignment: .leading, spacing: 12) {
                Text(variant.headerLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appInk)
                Divider()
                RecordValueEditor(
                    exercise: exercise,
                    equipment: variant.equipment,
                    isBodyweight: variant.isBodyweight,
                    executionType: variant.executionType,
                    trackingMode: variant.trackingMode,
                    isFollowAlong: variant.isFollowAlong,
                    existing: variant.record,
                    context: context,
                    onSaved: onSaved
                )
            }
        }
    }
}
