import SwiftUI
import SwiftData

/// A row's editable identity. EMOM/AMRAP entries have no settings of their own, but
/// still need a case here — Clone and Delete apply to every kind of row, so every row
/// gets a gear.
enum ExerciseSettingsTarget {
    case timeStep(TimeSectionStep)
    case repEntry(RepSectionExercise)
    case quickEntry(SectionExerciseEntry)
}

/// Everything one exercise is set to, shown in rust under its name — the per-exercise
/// counterpart to `sectionSettingsSummary`, and listed with the same always-visible
/// rule so a setting turned off still reads as off rather than disappearing.
///
/// Bodyweight and L/R are the exception: they're listed only for exercises the catalog
/// actually allows them for, matching the conditionals that gate the panel's rows —
/// an option that can't be turned on is noise, not information.
///
/// Execution type is a second exception, for the opposite reason: the row's *title* now
/// reads "Push Up, Explosive", so repeating it here would print the same word twice in
/// one row. The gear panel is still where it's set.
func exerciseSettingsSummary(_ target: ExerciseSettingsTarget) -> String? {
    var parts: [String] = []

    /// The equipment part, or nil where naming it would say nothing.
    ///
    /// Resolved rather than read straight off the entry: an entry that never picked one
    /// still gets loaded with the exercise's default, and a row that stays silent about
    /// that can't be used to check what a set will be logged against. Offered under the
    /// same `hasEquipmentChoice` rule the picker itself uses, so an exercise with one
    /// possibility doesn't gain a line naming it.
    func equipmentPart(
        exercise: Exercise?,
        preferredEquipment: Equipment?,
        prefersBodyweight: Bool
    ) -> String? {
        guard exercise?.hasEquipmentChoice == true || preferredEquipment != nil || prefersBodyweight
        else { return nil }
        let name = EquipmentSourcePicker.resolvedSourceName(
            exercise: exercise,
            preferredEquipment: preferredEquipment,
            prefersBodyweight: prefersBodyweight
        )
        return "Equipment: \(name)"
    }

    switch target {
    case .timeStep(let step):
        parts.append("\(step.durationSeconds)s")
        if step.stepType == .exercise {
            if let part = equipmentPart(
                exercise: step.exercise,
                preferredEquipment: step.preferredEquipment,
                prefersBodyweight: step.prefersBodyweight
            ) {
                parts.append(part)
            }
            // "default" is no longer a distinct state — an unset color resolves to a
            // real green selection, so name the color it actually shows as.
            parts.append("Color: \(step.resolvedColor.label)")
        }

    case .repEntry(let entry):
        parts.append("\(entry.targetSets) sets")
        // Rest applies in both tracking modes — the runner shows a rest timer for every
        // rep exercise regardless — so it's listed for both. Always a real number: an
        // unset custom rest still runs for the device default, and showing "default"
        // would hide the duration that actually applies.
        parts.append("rest \(entry.customRestSeconds ?? AppSettings.defaultRestSeconds)s")

        switch entry.trackingMode {
        case .repsWeight:
            parts.append("Track: reps & weight")
            if entry.exercise?.allowsBodyweight == true {
                // "Body option", not "Bodyweight": this is `allowsBodyweight` — whether the
                // stepper offers a Body position at all — and it would otherwise sit beside
                // an "Equipment: Bodyweight" meaning the different `prefersBodyweight`.
                parts.append("Body option: \(entry.allowsBodyweight ? "on" : "off")")
            }
            if entry.exercise?.isOneSided == true {
                parts.append("L/R: \(entry.tracksSides ? "on" : "off")")
            }
        case .maxHoldTime:
            parts.append("Track: max time")
            parts.append("Prep: \(entry.headStartSeconds)s")
        }

        // Outside the switch: a loaded hold is recorded against its equipment just as a
        // rep set is, and the picker is offered in both modes.
        if let part = equipmentPart(
            exercise: entry.exercise,
            preferredEquipment: entry.preferredEquipment,
            prefersBodyweight: entry.prefersBodyweight
        ) {
            parts.append(part)
        }

    case .quickEntry:
        // Execution type is the one setting these rows have, and the row's own title
        // already names it — see the note above `exerciseSettingsSummary`.
        break
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// Quick-adjust panel for a single exercise, opened by the gear on its row. Same
/// immediate-save behavior as the section editors' inline accordions this replaces —
/// every field writes straight through on change.
struct ExerciseSettingsPanel: View {
    let target: ExerciseSettingsTarget
    let context: ModelContext
    var onClone: () -> Void
    var onDelete: () -> Void
    /// Opens the exercise's own page. Handled by the card rather than here: a sheet
    /// presented from inside another sheet is torn down with its presenter, so the card
    /// closes this panel first and then presents.
    var onEditExercise: (() -> Void)?
    /// Only follow-along steps can gain a rest after them; nil everywhere else.
    var onAddRest: (() -> Void)?

    /// A rest already following this step means adding another would just stack two
    /// rests back to back — the same guard the section editor's inline editor applies.
    private var hasRestAfter: Bool {
        guard case .timeStep(let step) = target,
              let steps = step.section?.sortedTimeSteps,
              let index = steps.firstIndex(where: { $0.id == step.id }),
              index + 1 < steps.count
        else { return false }
        return steps[index + 1].stepType == .rest
    }

    /// A quick entry's only setting is its execution type, and an exercise that offers
    /// none leaves the panel with actions alone — no divider floating above an empty
    /// list.
    /// Every target has at least one setting now — a quick entry always has its rep
    /// count, so the divider above the actions row no longer comes and goes.
    private var hasSettings: Bool { true }

    /// Measured by `SettingsPanelSheet`; the paired rows split the width.
    @State private var contentSize: CGSize = .zero

    var body: some View {
        SettingsPanelSheet(contentSize: $contentSize) { panelContent }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleRow
            Divider()

            switch target {
            case .timeStep(let step):
                TimeStepSettingsRows(step: step, context: context)
            case .repEntry(let entry):
                RepEntrySettingsRows(entry: entry, context: context, halfColumn: SettingMetrics.halfColumn(for: contentSize.width))
            case .quickEntry(let entry):
                QuickEntrySettingsRows(entry: entry, context: context)
            }

            if hasSettings {
                Divider()
            }
            actionsRow

            SettingInfoDisclosure(entries: infoEntries)
        }
        // A settings panel changes; it doesn't perform. Rows that come and go with a
        // tracking mode appear where they belong rather than sliding or fading into
        // place. (The section panel drops this: its rest row *should* be seen arriving.)
        .transaction { $0.animation = nil }
    }

    /// Mirrors exactly the conditions the row groups above use to decide what to show —
    /// including each picker's own `hasChoice`, so a setting this exercise has nothing to
    /// offer for (no execution types attached, only one equipment) never gets explained
    /// as if it were on screen.
    private var infoEntries: [SettingInfoEntry] {
        switch target {
        case .timeStep(let step):
            var entries = [SettingInfoEntry("Duration", "How long this step lasts before moving to the next one.")]
            if step.stepType == .exercise {
                if step.exercise?.hasEquipmentChoice == true {
                    entries.append(SettingInfoEntry("Equipment", "What this exercise is loaded with — a specific piece of equipment, or bodyweight."))
                }
                if step.exercise?.isOneSided == true {
                    entries.append(SettingInfoEntry("Side", "Whether this trains one side at a time, and which side goes first."))
                }
                if !(step.exercise?.sortedExecutionTypes.isEmpty ?? true) {
                    entries.append(SettingInfoEntry("Execution", "How the exercise is performed, when it has more than one style to choose from."))
                }
                entries.append(SettingInfoEntry("Color", "The accent color this step's card shows during the workout."))
            }
            return entries

        case .repEntry(let entry):
            var entries: [SettingInfoEntry] = [
                SettingInfoEntry("Sets", "How many sets of this exercise the section calls for."),
                SettingInfoEntry("Rest", "How long to rest between sets."),
                SettingInfoEntry("Track", "Whether sets are logged as reps and weight, or as how long you can hold it.")
            ]
            if entry.trackingMode == .maxHoldTime {
                entries.append(SettingInfoEntry("Prep", "A head start before the hold timer starts counting."))
            }
            if entry.exercise?.hasEquipmentChoice == true {
                entries.append(SettingInfoEntry("Equipment", "What this exercise is loaded with — a specific piece of equipment, or bodyweight."))
            }
            if entry.exercise?.allowsBodyweight == true {
                entries.append(SettingInfoEntry("Bodyweight", "Lets this exercise's stepper offer an unloaded, bodyweight-only option."))
            }
            if entry.exercise?.isOneSided == true, entry.trackingMode == .repsWeight {
                entries.append(SettingInfoEntry("Track L/R", "Logs the left and right sides as separate sets instead of one."))
            }
            if !(entry.exercise?.sortedExecutionTypes.isEmpty ?? true) {
                entries.append(SettingInfoEntry("Execution", "How the exercise is performed, when it has more than one style to choose from."))
            }
            if entry.exercise?.progressionGroup != nil {
                entries.append(SettingInfoEntry("Progression", "Steps this exercise up or down its difficulty ladder automatically."))
            }
            return entries

        case .quickEntry(let entry):
            var entries = [SettingInfoEntry("Reps", "The target rep count shown for this exercise, if it has one.")]
            if entry.exercise?.isOneSided == true {
                entries.append(SettingInfoEntry("Side", "Whether this trains one side at a time, and which side goes first."))
            }
            if !(entry.exercise?.sortedExecutionTypes.isEmpty ?? true) {
                entries.append(SettingInfoEntry("Execution", "How the exercise is performed, when it has more than one style to choose from."))
            }
            return entries
        }
    }

    /// What this panel is about, so it isn't a list of values with no subject.
    ///
    /// The edit button leads it rather than sitting in the actions row below: it opens the
    /// *exercise*, not this workout's settings for it, so it belongs with the name.
    private var titleRow: some View {
        HStack(spacing: 8) {
            if let onEditExercise {
                Button(action: onEditExercise) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
            }
            Text(subjectTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }

    /// Straight from the row's own model, so the name here matches the row that opened it
    /// — execution type, rep count and all.
    private var subjectTitle: String {
        switch target {
        case .timeStep(let step): return step.displayTitle
        case .repEntry(let entry): return entry.displayTitle
        case .quickEntry(let entry): return entry.displayTitle
        }
    }

    private var actionsRow: some View {
        // Back to 28 now that Edit has moved up into the title row.
        HStack(spacing: 28) {
            if let onAddRest {
                actionButton("pause.circle", "Add Rest", tint: Color.appAccent, action: onAddRest)
                    .disabled(hasRestAfter)
            }
            actionButton("doc.on.doc", "Clone", tint: Color.appAccent, action: onClone)
            actionButton("trash", "Delete", tint: Color.appDanger, action: onDelete)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func actionButton(_ symbol: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.body)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared rows

/// One tappable setting: the title, then its current value in rust.
///
/// The whole row is the control — `SettingRowLabel` was already the readout, so making it
/// the target too means every setting looks and behaves the same whether it flips, opens a
/// wheel, or picks from a list.
struct SettingCell: View {
    let title: String
    let value: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowLabel(title: title, value: value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A number with ± either side of it, the shape `PersonalRecordEditView.numberRow` uses.
///
/// `.borderless` on the buttons is load-bearing: with `.plain`, a tap anywhere on the row
/// registers on both of them. The accent is on the buttons alone — putting it on the whole
/// `HStack`, as this once did, tinted the *label* green and was why stepper rows never
/// matched the rows around them.
struct SettingStepper: View {
    let title: String
    let value: String
    /// Rendered after `value` in a smaller size — the unit a measurement is in ("s",
    /// " min", " (min)"). nil where the value isn't a measurement at all: "off", "no",
    /// "x2" read as words or a multiplier rather than a number-plus-unit, and shrinking
    /// part of a word that isn't a unit would only make it harder to read.
    var unit: String? = nil
    /// Which fixed column to reserve for the title. Defaults to the full
    /// `SettingMetrics.labelColumn`, right for a stepper with a whole line to itself
    /// (Duration, Reps). A stepper squeezed into half a sheet's width alongside another
    /// setting passes the narrower `.compactLabelColumn` (Get Ready, Rest, Rounds,
    /// Repeat) or `.repStepperLabelColumn` (Sets, Prep) instead — either one frees up
    /// room the label alone would otherwise leave nothing for the ± buttons and value.
    var columnWidth: CGFloat = SettingMetrics.labelColumn
    let range: ClosedRange<Int>
    let step: Int
    @Binding var number: Int

    var body: some View {
        HStack(spacing: SettingMetrics.rowSpacing) {
            Text("\(title):")
                .font(.subheadline)
                .foregroundStyle(Color.appInk)
                .frame(width: columnWidth, alignment: .leading)
                .minimumScaleFactor(0.75)

            RepeatingStepButton(systemImage: "minus.circle", isDisabled: number <= range.lowerBound) {
                number = max(range.lowerBound, number - step)
            }

            valueText
                // Wide enough to hold "105s" at full size with room to spare — the
                // longest a Duration, Rest or Get Ready row's number ever reaches — so
                // the scale factor below is a safety net for the rarer, longer
                // combinations ("60 (min)") rather than something ordinary values lean on.
                .frame(minWidth: 40)
                .minimumScaleFactor(0.85)

            RepeatingStepButton(systemImage: "plus.circle", isDisabled: number >= range.upperBound) {
                number = min(range.upperBound, number + step)
            }

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `value` and `unit` as one run of text sharing a baseline, the unit a size down —
    /// the same idea `SetRowView` uses for a weight and its "kg". Concatenated rather
    /// than two separate `Text`s in the `HStack`, so `.frame`/`.minimumScaleFactor` above
    /// treat them as the one thing they read as.
    private var valueText: Text {
        let main = Text(value).font(.subheadline).monospacedDigit()
        let combined = unit.map { main + Text($0).font(.caption2) } ?? main
        return combined.foregroundColor(Color.appRust)
    }
}

/// A ± button that keeps stepping, faster and faster, for as long as it's held — so
/// closing the gap between 1 and a stepper's far end (`Repeat`'s 20, `Rounds`' 60) takes
/// a press-and-hold rather than dozens of taps.
///
/// Built on a press gesture rather than left to `Button`, which only ever reports a
/// completed tap — there's no "still held" signal a repeat timer could hang off of. The
/// gesture instead tracks touch-down and touch-up directly, firing `action` once
/// immediately (so a quick tap is exactly as responsive as it always was) and then again
/// on a `Timer` that re-schedules itself a little faster each time, down to a floor.
struct RepeatingStepButton: View {
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    /// How long the first repeat waits after the initial step — long enough that a quick
    /// tap and release never sees a second one land.
    private static let initialDelay: TimeInterval = 0.45
    /// The repeat's starting pace, once the initial delay has passed.
    private static let startInterval: TimeInterval = 0.32
    /// The fastest the repeat ever reaches, once fully accelerated.
    private static let minInterval: TimeInterval = 0.045
    /// How much shorter each successive interval gets — multiplicative, so the ramp-up
    /// feels continuous rather than snapping straight to full speed.
    private static let accelerationFactor: Double = 0.86

    @State private var timer: Timer?
    @State private var currentInterval: TimeInterval = startInterval

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(isDisabled ? Color.appAccent.opacity(0.35) : Color.appAccent)
            .contentShape(Rectangle())
            // `minimumDistance: 0` is what makes this a press gesture rather than a
            // drag — `onChanged` fires the instant the finger goes down, `onEnded` the
            // instant it lifts, with nothing in between required.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in start() }
                    .onEnded { _ in stop() }
            )
            // Held past a sheet dismissal or a scroll stealing the touch would otherwise
            // leave the timer running with nothing left to stop it.
            .onDisappear { stop() }
    }

    private func start() {
        guard timer == nil, !isDisabled else { return }
        action()
        currentInterval = Self.startInterval
        scheduleNext(after: Self.initialDelay)
    }

    private func scheduleNext(after delay: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            guard !isDisabled else { stop(); return }
            action()
            currentInterval = max(Self.minInterval, currentInterval * Self.accelerationFactor)
            scheduleNext(after: currentInterval)
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// A choice, rendered as a plain row rather than a `Picker`.
///
/// A menu-style `Picker` is a *control*: it carries the platform's minimum hit-target
/// height and its own content insets, so those rows sat visibly taller than the text rows
/// around them. Worse, `.tint` is its only knob and it colours the value *and* the chevron
/// together — there is no way to get a rust value with a green chevron out of one.
///
/// A `Menu` with a hand-built label has neither problem: the label is a `SettingRowLabel`
/// like every other row, so a menu row genuinely *is* a text row.
struct SettingMenu<Content: View>: View {
    let title: String
    let value: String
    /// Passed through to `SettingRowLabel` — see its own note on why a caller would want
    /// anything other than rust.
    var valueColor: Color = .appRust
    /// Lets the title and value sit together at the leading edge rather than spreading to
    /// the column's width. For a row standing on its own outside a panel, where there is
    /// nothing to line up with and a stretched row would strand its value across the page.
    var hugsTitle: Bool = false
    /// Forwarded to `SettingRowLabel` — see its own note on `columnWidth`.
    var columnWidth: CGFloat = SettingMetrics.labelColumn
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                SettingRowLabel(
                    title: title,
                    value: value,
                    hugsTitle: hugsTitle,
                    columnWidth: columnWidth,
                    valueColor: valueColor
                )
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.appAccent)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        // iOS reverses a menu's items when it opens upward, so the first option would land
        // at the bottom depending only on where the row sits on screen.
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Time steps

private struct TimeStepSettingsRows: View {
    @Bindable var step: TimeSectionStep
    let context: ModelContext

    /// Get Ready can be skipped entirely (0s); a real exercise or rest can't.
    private var durationRange: ClosedRange<Int> {
        step.stepType == .getReady ? 0...300 : 5...600
    }

    @ViewBuilder
    var body: some View {
        SettingStepper(
            title: "Duration",
            value: "\(step.durationSeconds)",
            unit: "s",
            range: durationRange,
            step: 5,
            number: Binding(
                get: { step.durationSeconds },
                set: { step.durationSeconds = $0; save() }
            )
        )

        // Rest and Get Ready stay plain gray in the lists — no color to pick.
        if step.stepType == .exercise {
            // What the step is loaded with. Same picker the rep entry uses, and the same
            // reason it matters here: naming the equipment is what lets a held weight be
            // recorded at the end of the workout.
            EquipmentSourcePicker(step: step, context: context)

            // Set here and nowhere else: a Follow Along step's execution type is fixed
            // for the whole run, so the builder is the only place it can be chosen.
            SidePicker(
                exercise: step.exercise,
                selection: Binding(
                    get: { step.side },
                    set: { step.side = $0; save() }
                )
            )

            ExecutionTypePicker(
                options: step.exercise?.sortedExecutionTypes ?? [],
                selection: Binding(
                    get: { step.executionType },
                    set: { step.executionType = $0; save() }
                )
            )

            // Last, because it's the only two-line row: the swatch strip needs 246pt and
            // so can't sit beside the label column, and a full-bleed block reads better
            // closing the panel than interrupting the middle of it.
            VStack(alignment: .leading, spacing: 8) {
                // Spacer and full width like every other row here, not a bare
                // `SettingRowLabel`: on its own the label hugged its content, and a
                // hugged proposal is exactly what `SettingRowLabel`'s
                // `minimumScaleFactor` reads as "not enough room" — so this row's value
                // rendered a size down from the rest of the panel.
                SettingRowLabel(title: "Color", value: step.resolvedColor.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Back to the default 28pt: the 22 here was a workaround for the 300pt
                // popover this panel used to be, where 8 swatches overflowed the width.
                PaletteColorPicker(selection: Binding(
                    get: { step.color },
                    set: { step.color = $0; save() }
                ), defaultSelection: step.resolvedColor)
            }
        }
    }

    private func save() {
        step.markDirty()
        try? context.save()
    }
}

// MARK: - Quick exercises (EMOM/AMRAP)

/// Reps and execution type. EMOM and AMRAP share a single timer across every exercise, so
/// there is nothing about *timing* to set per exercise — but what you do in that minute is
/// still per exercise.
private struct QuickEntrySettingsRows: View {
    @Bindable var entry: SectionExerciseEntry
    let context: ModelContext

    @ViewBuilder
    var body: some View {
        // 0 is a real choice, not an empty state: an EMOM can legitimately say "burpees
        // for a minute" with no target, and every entry written before reps existed is 0.
        SettingStepper(
            title: "Reps",
            value: entry.targetReps > 0 ? "\(entry.targetReps)" : "none",
            range: 0...100,
            step: 1,
            number: Binding(
                get: { entry.targetReps },
                set: { entry.targetReps = $0; save() }
            )
        )

        SidePicker(
            exercise: entry.exercise,
            selection: Binding(
                get: { entry.side },
                set: { entry.side = $0; save() }
            )
        )

        ExecutionTypePicker(
            options: entry.exercise?.sortedExecutionTypes ?? [],
            selection: Binding(
                get: { entry.executionType },
                set: { entry.executionType = $0; save() }
            )
        )
    }

    private func save() {
        entry.markDirty()
        try? context.save()
    }
}

// MARK: - Rep exercises

private struct RepEntrySettingsRows: View {
    @Bindable var entry: RepSectionExercise
    let context: ModelContext
    /// Passed in rather than read from `SettingMetrics`: only the panel knows how wide the
    /// sheet turned out to be, and both halves must agree on the same number.
    let halfColumn: CGFloat

    /// Storing `nil` when the value matches the device default keeps the entry
    /// following that default if it later changes, rather than freezing today's value.
    private var restBinding: Binding<Int> {
        Binding(
            get: { entry.customRestSeconds ?? AppSettings.defaultRestSeconds },
            set: { newValue in
                entry.customRestSeconds = newValue == AppSettings.defaultRestSeconds ? nil : newValue
                save()
            }
        )
    }

    @ViewBuilder
    var body: some View {
        // Sets and Rest pair off because they are the two numbers every rep entry has —
        // reading them side by side is how you check "3 x 90s" in one glance instead of two.
        // Both halves fixed rather than flexible: left to the layout, a menu beside a
        // stepper splits differently than two steppers do, which is how Prep and Rest
        // ended up disagreeing about where the second column starts.
        HStack(spacing: SettingMetrics.pairSpacing) {
            SettingStepper(
                title: "Sets",
                value: "\(entry.targetSets)",
                columnWidth: SettingMetrics.repStepperLabelColumn,
                range: 1...20,
                step: 1,
                number: Binding(
                    get: { entry.targetSets },
                    set: { entry.targetSets = $0; save() }
                )
            )
            .frame(width: halfColumn)

            SettingStepper(
                title: "Rest",
                value: "\(restBinding.wrappedValue)",
                unit: "s",
                columnWidth: SettingMetrics.repStepperLabelColumn,
                range: 0...600,
                step: 15,
                number: restBinding
            )
            .frame(width: halfColumn)
        }

        // Prep shares this row: it only exists for max time, and pairing it with the
        // choice that reveals it keeps them read as one setting.
        HStack(spacing: SettingMetrics.pairSpacing) {
            // Always uses Sets' own column, even in the mode where Prep is hidden: the
            // row keeps the same two-column split as Sets/Rest above it, so switching
            // modes changes what sits in the right half and never where the left half is.
            //
            // Matching `repStepperLabelColumn` here is what actually keeps that promise
            // for the label itself: with the full column, "track:" claimed as much room
            // as Bodyweight/Execution below it, leaving too little for "Max time" and
            // shrinking it — while "Rep", short enough to fit either way, never did.
            SettingMenu(
                title: "track",
                value: entry.trackingMode == .repsWeight ? "Rep" : "Max time",
                columnWidth: SettingMetrics.repStepperLabelColumn
            ) {
                Button("Reps and weights") { entry.trackingMode = .repsWeight; save() }
                Button("Max time") { entry.trackingMode = .maxHoldTime; save() }
            }
            .frame(width: halfColumn)

            // Hidden rather than removed, so the right half keeps exactly the width it
            // would have had. An `if` here let the menu stretch across the whole row and
            // jump sideways on every mode change.
            prepStepper
                .frame(width: halfColumn)
                .opacity(entry.trackingMode == .maxHoldTime ? 1 : 0)
                .disabled(entry.trackingMode != .maxHoldTime)
                .accessibilityHidden(entry.trackingMode != .maxHoldTime)
        }

        // Offered in both tracking modes: a max-time hold can be loaded too (a weighted
        // plank), and bodyweight is one of the choices rather than a separate toggle.
        EquipmentSourcePicker(entry: entry, context: context)

        // Distinct from the catalog's "Allow bodyweight", which lives on the exercise page:
        // that one says the exercise *can* be done unloaded, this one says this workout
        // offers the Body position on its stepper. The catalog flag is what unlocks it,
        // which is why the row only appears once it's set.
        if entry.exercise?.allowsBodyweight == true {
            SettingCell(title: "Bodyweight", value: entry.allowsBodyweight ? "on" : "off") {
                entry.allowsBodyweight.toggle()
                save()
            }
        }

        // Kept next to Bodyweight rather than further down: both are catalog capabilities
        // this entry opts into, and neither row exists without its flag on the exercise.
        if entry.exercise?.isOneSided == true, entry.trackingMode == .repsWeight {
            SettingCell(title: "Track L/R", value: entry.tracksSides ? "on" : "off") {
                entry.tracksSides.toggle()
                save()
            }
        }

        // The workout's default. The runner can still override it in the moment, right up
        // until the first set is logged.
        ExecutionTypePicker(
            options: entry.exercise?.sortedExecutionTypes ?? [],
            selection: Binding(
                get: { entry.executionType },
                set: { entry.executionType = $0; save() }
            )
        )

        if entry.exercise?.progressionGroup != nil {
            SettingCell(title: "Progression", value: entry.progressionEnabled ? "on" : "off") {
                entry.progressionEnabled.toggle()
                save()
            }
        }
    }

    /// Pulled out of `body` because it is rendered in both tracking modes — visible in one
    /// and holding its space in the other.
    private var prepStepper: some View {
        SettingStepper(
            title: "Prep",
            value: "\(entry.headStartSeconds)",
            unit: "s",
            columnWidth: SettingMetrics.repStepperLabelColumn,
            range: 0...30,
            step: 1,
            number: Binding(
                get: { entry.headStartSeconds },
                set: { entry.headStartSeconds = $0; save() }
            )
        )
    }

    private func save() {
        entry.markDirty()
        try? context.save()
    }
}
