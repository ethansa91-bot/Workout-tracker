import SwiftUI
import SwiftData

/// The value-entry engine every "set a record" flow uses: weight/reps or weight/time,
/// stepped or wheeled, gated to only ever save something that actually beats the
/// standing record.
///
/// Shared by `AddPersonalRecordSheet` (where the combination is picked fresh) and the
/// record page's own inline corrector (where the combination is already fixed by which
/// section's pencil was tapped) — one engine, so the two can't disagree about how a
/// record is entered or when Save unlocks. Everything here was `PersonalRecordEditView`
/// itself before the record page split into a variant list plus this.
struct RecordValueEditor: View {
    let exercise: Exercise
    let equipment: Equipment?
    let isBodyweight: Bool
    let executionType: ExecutionType?
    let trackingMode: RepExerciseTrackingMode
    let isFollowAlong: Bool
    /// The record this editor is correcting — nil starts a new one. Re-passed in by the
    /// caller after every save rather than owned here, so the caller's own list of
    /// variants (or saved-combinations menu) stays the single source of truth for which
    /// record a given combination resolves to.
    let existing: PersonalRecord?
    let context: ModelContext
    /// Called with the freshly saved record, so the caller can refresh whatever it's
    /// showing without this view owning any of that state itself.
    let onSaved: (PersonalRecord) -> Void

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var holdSeconds: Int = 0
    @State private var showingRepsWheel = false
    @State private var showingTimeWheel = false
    @State private var hasSeeded = false

    /// Everything that decides what this editor should be showing. Re-seeds whenever any
    /// of it changes — including `existing`'s id turning from nil into a real one right
    /// after the first save, which harmlessly reloads the value just written.
    private struct SeedKey: Equatable {
        let equipmentID: UUID?
        let isBodyweight: Bool
        let executionTypeID: UUID?
        let trackingMode: RepExerciseTrackingMode
        let recordID: UUID?
    }

    private var seedKey: SeedKey {
        SeedKey(
            equipmentID: equipment?.id,
            isBodyweight: isBodyweight,
            executionTypeID: executionType?.id,
            trackingMode: trackingMode,
            recordID: existing?.id
        )
    }

    var body: some View {
        Group {
            valueSection
            saveSection
        }
        .onAppear {
            guard !hasSeeded else { return }
            hasSeeded = true
            seed()
        }
        .onChange(of: seedKey) { seed() }
    }

    // MARK: - Value controls

    @ViewBuilder
    private var valueSection: some View {
        if isFollowAlong {
            // The step's duration belongs to the plan, so the load is the whole record
            // — there is no second value to enter.
            weightControl(isLast: true)
        } else {
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

    /// The one shape every number here takes: a label, then ⊖ value ⊕. The value itself
    /// is a button wherever a wheel is offered, so a big jump doesn't mean forty taps.
    ///
    /// `.borderless` on the buttons is load-bearing: a `List` row with plain buttons in
    /// it treats a tap anywhere on the row as a tap on all of them.
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
    /// presets, walkable in a few taps, and a wheel couldn't carry the option colour
    /// dots.
    ///
    /// Option-based equipment has no typed entry at all — its ladder *is* the set of
    /// values, so there is nothing to type that the ± keys can't reach. A record already
    /// holding an off-ladder value still displays (as "opt. N") and still steps: the
    /// first ± snaps it onto the nearest rung in that direction.
    @ViewBuilder
    private func weightControl(isLast: Bool) -> some View {
        let usesOptions = equipment?.usesOptions == true
        let options = equipment?.sortedWeightCombos ?? []
        numberRow(usesOptions ? "Option" : "Weight", onStep: { step($0, options: options) }) {
            weightDisplay.frame(minWidth: 88)
        }
        .formRow(isLast: isLast)
    }

    /// `allowsBodyweight: false` on purpose — bodyweight is an explicit choice on the
    /// caller's own equipment selector, so the ladder must not slide off its bottom into
    /// it behind that selector's back. `.offerBodyweight` can never come back here.
    private func step(_ delta: Int, options: [WeightCombo]) {
        guard case .weight(let value, _) = steppedSetWeight(
            delta: delta,
            weight: weight,
            isBodyweight: false,
            options: options,
            allowsBodyweight: false
        ) else { return }
        weight = value
    }

    /// Option-based equipment shows the matching option's colour dot and name — the dot
    /// stays here, where an option is being compared against history rather than
    /// stepped mid-set; everything else shows "value unit".
    @ViewBuilder
    private var weightDisplay: some View {
        if let equipment, equipment.usesOptions {
            let combo = equipment.sortedWeightCombos.first(where: { $0.value == weight })
            HStack(spacing: 4) {
                if let color = combo?.color {
                    Circle().fill(color.color).frame(width: 8, height: 8)
                }
                Text(WeightCombo.optionDisplayName(for: weight, in: equipment.sortedWeightCombos))
                    .foregroundStyle(Color.appInk)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text(formattedSetWeight(weight, unit: weightUnit))
                .foregroundStyle(Color.appInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var weightUnit: String {
        equipment?.effectiveWeightUnit ?? AppSettings.weightUnit
    }

    // MARK: - Save

    /// A brand-new record has to hold something; the gate below would otherwise let an
    /// empty one through, since anything beats no record at all.
    private var hasValue: Bool {
        if isFollowAlong { return weight > 0 }
        return trackingMode == .maxHoldTime ? holdSeconds > 0 : reps > 0
    }

    /// Only a value that actually beats the standing record can be saved — heavier, or
    /// more reps at the same weight, or a longer hold. Straight through
    /// `PersonalRecordQueries.beats`, the same ranking a set logged in a session is
    /// promoted by, so the two can't disagree about what counts as a record.
    private var canSave: Bool {
        guard hasValue else { return false }
        return PersonalRecordQueries.beats(
            record: existing,
            trackingMode: trackingMode,
            reps: isFollowAlong || trackingMode == .maxHoldTime ? nil : reps,
            weight: isBodyweight ? nil : weight,
            holdSeconds: isFollowAlong ? nil : (trackingMode == .maxHoldTime ? holdSeconds : nil),
            isBodyweight: isBodyweight,
            isFollowAlong: isFollowAlong
        )
    }

    /// A plain group rather than a `Section` — this view is embedded two ways: as a
    /// top-level row in `AddPersonalRecordSheet`'s own `List` (where a `Section` would
    /// be fine) and nested inside one row of the record page's own per-variant card
    /// (where a `Section` isn't a List's direct child and wouldn't render as one). One
    /// shape that works in both rather than two versions of this view.
    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                save()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            // Same solid, dark-green, rounded-rect look as `PersonalRecordEditView`'s own
            // Add Record button — no explicit tint/foreground override, so it renders
            // identically instead of reading as a lighter, glassier variant. `.disabled`
            // alone gives the "can't save yet" state its dimming.
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .disabled(!canSave)
            .formRow()

            Text("Save unlocks once the value beats the current record.")
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
                .formRowPadding()
        }
    }

    /// Routed through `PersonalRecordQueries.setRecord` rather than mutating in place, so
    /// replacing a value files the old one into history instead of destroying it.
    private func save() {
        guard canSave else { return }
        // Stamped rather than re-derived at display time, so the number keeps its
        // meaning if the exercise's equipment changes later.
        let unit = isBodyweight ? nil : weightUnit
        let saved = PersonalRecordQueries.setRecord(
            for: exercise,
            equipment: equipment,
            executionType: executionType,
            existing: existing,
            trackingMode: trackingMode,
            // A hold has no rep count, and a rep record has no hold — each carries only
            // what its own shape means.
            reps: isFollowAlong || trackingMode == .maxHoldTime ? nil : reps,
            weight: isBodyweight ? nil : weight,
            holdSeconds: isFollowAlong ? nil : (trackingMode == .maxHoldTime ? holdSeconds : nil),
            isBodyweight: isBodyweight,
            isFollowAlong: isFollowAlong,
            weightUnit: unit,
            context: context
        )
        onSaved(saved)
    }

    // MARK: - Seeding

    private func seed() {
        if let existing {
            weight = existing.weight ?? 0
            reps = existing.reps ?? 0
            holdSeconds = existing.holdSeconds ?? 0
        } else {
            seedFromHistory()
        }
    }

    /// No saved record yet: fall back to the best this exercise was actually logged at
    /// on this equipment, and failing that to the lightest weight the equipment offers —
    /// so picking an equipment you've never set a record on starts at its first notch
    /// rather than at nothing.
    private func seedFromHistory() {
        let lightest = equipment?.sortedWeightCombos.first?.value ?? 0
        // Scoped to match the record being seeded, so an exercise splitting by type
        // doesn't offer one type's history as the starting point for another's.
        let splits = exercise.splitsRecordsByExecutionType || executionType != nil
        switch trackingMode {
        case .maxHoldTime:
            reps = 0
            holdSeconds = SetLogQueries.bestHoldEver(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, context: context) ?? 0
            weight = isBodyweight ? 0 : lightest
        case .repsWeight:
            holdSeconds = 0
            if isBodyweight {
                reps = SetLogQueries.bestBodyweightRepsEver(exercise: exercise, executionType: executionType, scopesByExecutionType: splits, context: context) ?? 0
                weight = 0
            } else if let best = SetLogQueries.bestSetEver(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, context: context) {
                weight = best.weight
                reps = best.reps
            } else {
                weight = lightest
                reps = 0
            }
        }
    }
}
