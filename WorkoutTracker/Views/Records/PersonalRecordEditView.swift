import SwiftUI
import SwiftData

/// One exercise's personal records, with the two things that decide *which* record you
/// are looking at as selectable lines at the top: the equipment it was set on, and
/// whether it's a weight/reps best or a max hold. Everything below — the value controls,
/// the Save gate and the history — follows that selection.
///
/// Absent a saved record for the chosen combination the form prefills from session
/// history, and absent that from the equipment's lightest preset, so a new record starts
/// somewhere real rather than at zero.
struct PersonalRecordEditView: View {
    /// Which load a record belongs to. Mirrors the session runner's `WeightSource` minus
    /// its manual case — a typed-in weight carries no equipment, so a record written from
    /// one has no key to file under.
    private enum RecordSource: Hashable {
        case equipment(UUID)
        case bodyweight
        /// Records saved before records were kept per equipment. Offered in the menu only
        /// while it's already the selection, so it can be returned to but never newly chosen.
        case none
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The sheet path needs a stack of its own for its title and Done; the push path
    /// already has the Records list's, and nesting a second one there swallowed the back
    /// button and made `dismiss()` pop the wrong stack.
    var isPresentedAsSheet: Bool = false

    /// nil only on the add path, until the exercise line picks one.
    @State private var exercise: Exercise?
    @State private var source: RecordSource
    @State private var trackingMode: RepExerciseTrackingMode
    @State private var loadedRecord: PersonalRecord?
    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var holdSeconds: Int = 0
    /// Level-based equipment only: true when the value sits off the level ladder, which
    /// swaps the stepper for a typed field so an off-ladder level stays editable.
    @State private var useCustomWeight = false
    @State private var showingExercisePicker = false
    @State private var showingRepsWheel = false
    @State private var showingTimeWheel = false
    @State private var hasLoaded = false

    /// Kept so a record whose equipment has since been detached from the exercise still
    /// opens on the right one — `equipmentItems` would no longer resolve it.
    private let initialEquipment: Equipment?
    /// Only the add path lets the exercise change; opened from the Records list the title
    /// band already names it, and swapping it there would silently retarget the edit.
    private let allowsExerciseChange: Bool

    init(
        exercise: Exercise? = nil,
        equipment: Equipment? = nil,
        isBodyweight: Bool = false,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        isPresentedAsSheet: Bool = false
    ) {
        self.isPresentedAsSheet = isPresentedAsSheet
        self.initialEquipment = equipment
        self.allowsExerciseChange = exercise == nil
        _exercise = State(initialValue: exercise)
        _trackingMode = State(initialValue: trackingMode)
        if isBodyweight {
            _source = State(initialValue: .bodyweight)
        } else if let equipment {
            _source = State(initialValue: .equipment(equipment.id))
        } else {
            _source = State(initialValue: .none)
        }
    }

    var body: some View {
        if isPresentedAsSheet {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            if allowsExerciseChange {
                GlassButtonRow(
                    systemImage: "figure.strengthtraining.traditional",
                    title: "Exercise",
                    value: exercise?.displayName ?? "Choose…"
                ) {
                    showingExercisePicker = true
                }
                .formRow(isLast: false)
            }

            GlassMenuRow(
                systemImage: isBodyweight ? "figure.strengthtraining.functional" : "dumbbell.fill",
                title: "Equipment",
                value: equipmentLabel,
                isEnabled: exercise != nil
            ) {
                equipmentMenu
            }
            .formRow(isLast: false)

            GlassMenuRow(
                systemImage: "trophy.fill",
                title: "Record type",
                value: trackingMode == .maxHoldTime ? "Max Time" : "Weight & Reps",
                isEnabled: exercise != nil
            ) {
                Button("Weight & Reps") { trackingMode = .repsWeight }
                Button("Max Time") { trackingMode = .maxHoldTime }
            }
            .formRow(isLast: false)

            valueSection
            saveSection
            historySection
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(title: exercise?.displayName ?? "New Record")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedAsSheet {
                // "Done", not "Cancel": saving happens in the page now, so by the time
                // this is tapped the work is already committed.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            // No `excluding:` — an exercise that already has a barbell record is exactly
            // the one you'd reach for to add a dumbbell one.
            ExercisePickerView { picked in
                exercise = picked
                source = defaultSource(for: picked)
                reload()
            }
        }
        .onChange(of: source) { reload() }
        .onChange(of: trackingMode) { reload() }
        .onAppear {
            // Guarded: a push can re-appear, and reloading then would throw away edits
            // the user came back to finish.
            guard !hasLoaded else { return }
            hasLoaded = true
            reload()
        }
    }

    // MARK: - Selection

    private var isBodyweight: Bool { source == .bodyweight }

    /// Looked up on the exercise, falling back to whatever the caller handed over — a
    /// record can outlive its equipment being detached, and it still has to open on it.
    private var selectedEquipment: Equipment? {
        guard case .equipment(let id) = source else { return nil }
        if let match = exercise?.equipmentItems.first(where: { $0.id == id }) { return match }
        return initialEquipment?.id == id ? initialEquipment : nil
    }

    /// The exercise's weighted equipment, plus the current selection when it isn't among
    /// them — otherwise switching away from an unusual record would be a one-way door.
    private var equipmentOptions: [Equipment] {
        guard let exercise else { return [] }
        var options = exercise.weightedEquipmentOptions
        if let current = selectedEquipment, !options.contains(where: { $0.id == current.id }) {
            options.insert(current, at: 0)
        }
        return options
    }

    @ViewBuilder
    private var equipmentMenu: some View {
        ForEach(equipmentOptions) { item in
            Button(item.name) { source = .equipment(item.id) }
        }
        if exercise?.allowsBodyweightSource == true {
            Button("Bodyweight") { source = .bodyweight }
        }
        if source == RecordSource.none {
            Button("No equipment") { source = .none }
        }
    }

    private var equipmentLabel: String {
        switch source {
        case .bodyweight: return "Bodyweight"
        case .none: return "No equipment"
        case .equipment: return selectedEquipment?.name ?? "No equipment"
        }
    }

    private func defaultSource(for exercise: Exercise) -> RecordSource {
        if let resolved = exercise.weightedEquipment { return .equipment(resolved.id) }
        return .bodyweight
    }

    private var weightUnit: String {
        selectedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit
    }

    // MARK: - Value controls

    @ViewBuilder
    private var valueSection: some View {
        if exercise != nil {
            switch trackingMode {
            case .repsWeight:
                if !isBodyweight {
                    weightControl(isLast: false)
                }
                repsRow.formRow()
            case .maxHoldTime:
                // Weight first, then the time — the order the record reads in
                // (`20 kg × 60s`) and the order the hold card logs it in.
                if !isBodyweight {
                    weightControl(isLast: false)
                }
                timeRow.formRow()
            }
        }
    }

    /// The one shape every number on this page takes: a label, then ⊖ value ⊕. The value
    /// itself is a button wherever a wheel is offered, so a big jump doesn't mean forty taps.
    ///
    /// `.borderless` on the buttons is load-bearing: a `List` row with plain buttons in it
    /// treats a tap anywhere on the row as a tap on all of them.
    @ViewBuilder
    private func numberRow<Value: View>(
        _ label: String,
        onStep: @escaping (Int) -> Void,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer()
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            value()
            Button {
                onStep(1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Color.appAccent)
    }

    /// The value rendered as a button that opens its wheel.
    ///
    /// The popover hangs off the button rather than the row: attached to the enclosing
    /// `HStack` it presents from the full row width and points at the wrong place.
    private func wheelValue<Wheel: View>(
        _ text: String,
        isPresented: Binding<Bool>,
        @ViewBuilder wheel: @escaping () -> Wheel
    ) -> some View {
        Button {
            isPresented.wrappedValue = true
        } label: {
            Text(text)
                .foregroundStyle(Color.appInk)
                .frame(minWidth: 88)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: isPresented) { wheel() }
    }

    private var repsRow: some View {
        numberRow("Reps", onStep: { reps = min(200, max(0, reps + $0)) }) {
            wheelValue("\(reps)", isPresented: $showingRepsWheel) {
                GlassNumberWheel(title: "Reps", value: $reps, range: 0...200) { "\($0) reps" }
            }
        }
    }

    private var timeRow: some View {
        numberRow("Max time", onStep: { holdSeconds = min(3600, max(0, holdSeconds + $0)) }) {
            wheelValue("\(holdSeconds)s", isPresented: $showingTimeWheel) {
                GlassNumberWheel(title: "Max time", value: $holdSeconds, range: 0...3600) { "\($0)s" }
            }
        }
    }

    /// Steps through the selected equipment's presets rather than taking a typed number,
    /// so the record is set the same way the set that earns it is logged.
    ///
    /// The only number here with no wheel: its ladder is the equipment's own handful of
    /// presets, walkable in a few taps, and a wheel couldn't carry the level colour dots.
    @ViewBuilder
    private func weightControl(isLast: Bool) -> some View {
        let equipment = selectedEquipment
        let isLevelBased = equipment?.isLevelBased == true
        if isLevelBased {
            Toggle("Custom value", isOn: $useCustomWeight)
                .formRow(isLast: false)
        }
        if isLevelBased && useCustomWeight {
            HStack {
                Text("Level")
                Spacer()
                TextField("Value", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            .formRow(isLast: isLast)
        } else {
            let options = equipment?.sortedWeightCombos ?? []
            numberRow(isLevelBased ? "Level" : "Weight", onStep: { step($0, options: options) }) {
                weightDisplay.frame(minWidth: 88)
            }
            .formRow(isLast: isLast)
        }
    }

    /// `allowsBodyweight: false` on purpose — bodyweight is an explicit choice on the
    /// equipment line here, so the ladder must not slide off its bottom into it behind
    /// the selector's back.
    private func step(_ delta: Int, options: [WeightCombo]) {
        weight = steppedSetWeight(
            delta: delta,
            weight: weight,
            isBodyweight: false,
            options: options,
            allowsBodyweight: false
        ).weight
    }

    /// Level-based equipment shows the matching level's color dot and name, the way a set
    /// row does; everything else shows "value unit".
    @ViewBuilder
    private var weightDisplay: some View {
        if let equipment = selectedEquipment, equipment.isLevelBased {
            if let combo = equipment.sortedWeightCombos.first(where: { $0.value == weight }) {
                HStack(spacing: 4) {
                    if let color = combo.color {
                        Circle().fill(color.color).frame(width: 8, height: 8)
                    }
                    Text(combo.levelDisplayName)
                        .foregroundStyle(Color.appInk)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text("Level \(Int(weight))")
                    .foregroundStyle(Color.appInk)
            }
        } else {
            Text(formattedSetWeight(weight, unit: weightUnit))
                .foregroundStyle(Color.appInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Save

    /// A brand-new record has to hold something; the gate below would otherwise let an
    /// empty one through, since anything beats no record at all.
    private var hasValue: Bool {
        trackingMode == .maxHoldTime ? holdSeconds > 0 : reps > 0
    }

    /// Only a value that actually beats the standing record can be saved — heavier, or
    /// more reps at the same weight, or a longer hold. Straight through
    /// `PersonalRecordQueries.beats`, the same ranking a set logged in a session is
    /// promoted by, so the two can't disagree about what counts as a record.
    private var canSave: Bool {
        guard exercise != nil, hasValue else { return false }
        return PersonalRecordQueries.beats(
            record: loadedRecord,
            trackingMode: trackingMode,
            reps: trackingMode == .maxHoldTime ? nil : reps,
            weight: isBodyweight ? nil : weight,
            holdSeconds: trackingMode == .maxHoldTime ? holdSeconds : nil,
            isBodyweight: isBodyweight
        )
    }

    @ViewBuilder
    private var saveSection: some View {
        if exercise != nil {
            Section {
                Button {
                    save()
                } label: {
                    Text("Save")
                        .foregroundStyle(canSave ? Color.appAccent : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.appAccent.opacity(0.25))
                .disabled(!canSave)
                .formRow()
            } footer: {
                FormSectionFooter("Save unlocks once the value beats the current record.")
            }
        }
    }

    /// Routed through `PersonalRecordQueries.setRecord` rather than mutating in place, so
    /// replacing a value files the old one into history instead of destroying it.
    ///
    /// Stays on the page: the point of saving here is to see the result — the history
    /// gains a row and Save locks again, because the form now matches the record.
    private func save() {
        guard let exercise, canSave else { return }
        // Stamped rather than re-derived at display time, so the number keeps its meaning
        // if the exercise's equipment changes later.
        let unit = isBodyweight ? nil : weightUnit
        loadedRecord = PersonalRecordQueries.setRecord(
            for: exercise,
            equipment: selectedEquipment,
            existing: loadedRecord,
            trackingMode: trackingMode,
            // A hold has no rep count, and a rep record has no hold — each carries only
            // what its own shape means.
            reps: trackingMode == .maxHoldTime ? nil : reps,
            weight: isBodyweight ? nil : weight,
            holdSeconds: trackingMode == .maxHoldTime ? holdSeconds : nil,
            isBodyweight: isBodyweight,
            weightUnit: unit,
            context: context
        )
    }

    // MARK: - Loading

    /// Re-resolves the record behind the current selection and re-seeds the form from it.
    /// Called whenever the equipment, the record type or the exercise changes — those are
    /// the three things that decide which record this page is editing.
    private func reload() {
        guard let exercise else {
            loadedRecord = nil
            return
        }
        let equipment = selectedEquipment
        let record = PersonalRecordQueries.current(
            for: exercise,
            equipment: equipment,
            trackingMode: trackingMode,
            isBodyweight: isBodyweight,
            context: context
        )
        loadedRecord = record

        if let record {
            weight = record.weight ?? 0
            reps = record.reps ?? 0
            holdSeconds = record.holdSeconds ?? 0
        } else {
            seedFromHistory(exercise: exercise, equipment: equipment)
        }

        // An off-ladder value has no level to step to, so the typed field is the only
        // control that can represent it.
        useCustomWeight = equipment?.isLevelBased == true
            && weight != 0
            && !equipment!.sortedWeightCombos.contains { $0.value == weight }
    }

    /// No saved record yet: fall back to the best this exercise was actually logged at on
    /// this equipment, and failing that to the lightest weight the equipment offers — so
    /// picking an equipment you've never set a record on starts at its first notch rather
    /// than at nothing.
    private func seedFromHistory(exercise: Exercise, equipment: Equipment?) {
        let lightest = equipment?.sortedWeightCombos.first?.value ?? 0
        switch trackingMode {
        case .maxHoldTime:
            reps = 0
            holdSeconds = SetLogQueries.bestHoldEver(exercise: exercise, equipment: equipment, context: context) ?? 0
            weight = isBodyweight ? 0 : lightest
        case .repsWeight:
            holdSeconds = 0
            if isBodyweight {
                reps = SetLogQueries.bestBodyweightRepsEver(exercise: exercise, context: context) ?? 0
                weight = 0
            } else if let best = SetLogQueries.bestSetEver(exercise: exercise, equipment: equipment, context: context) {
                weight = best.weight
                reps = best.reps
            } else {
                weight = lightest
                reps = 0
            }
        }
    }

    // MARK: - History

    /// The record's progression, newest first: the standing record, then every value it
    /// superseded. Read-only below the top row — history is a log of what actually
    /// happened rather than something to revise.
    ///
    /// Shown as soon as there is a saved record, even with no history behind it: the row
    /// carries the date the record was set, which nothing else on the page does.
    @ViewBuilder
    private var historySection: some View {
        if let record = loadedRecord {
            Section {
                // A record carries no achievement date of its own, so `updatedAt` is the
                // best stamp available — the same one `setRecord` files superseded values
                // under. Not swipe-deletable: removing the record itself is the Records
                // list's swipe, and doing it here would leave the page editing nothing.
                historyRow(
                    text: PersonalRecordFormatting.summary(record),
                    date: record.updatedAt,
                    isCurrent: true
                )
                // Already filtered of tombstones and sorted newest first by the getter.
                ForEach(record.history) { entry in
                    historyRow(
                        text: historySummary(entry),
                        date: entry.achievedAt,
                        isCurrent: false
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            SyncDeletion.delete(entry, context: context)
                            try? context.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                FormSectionHeader("Record Progression")
            } footer: {
                FormSectionFooter("Each time this record is beaten — here or during a workout — the value it replaced is kept with the date it was set.")
            }
        }
    }

    private func historyRow(text: String, date: Date, isCurrent: Bool) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.appInk)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func historySummary(_ entry: PersonalRecordEntry) -> String {
        PersonalRecordFormatting.summary(entry)
    }
}
