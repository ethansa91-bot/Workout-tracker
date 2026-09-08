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
    /// Toggled by the gray Info icon in `actionsRow` — `SettingInfoDisclosure` is just
    /// the entry list now, so the panel owns showing/hiding it itself.
    @State private var showingSettingInfo = false

    var body: some View {
        SettingsPanelSheet(contentSize: $contentSize) { proxy in panelContent(proxy: proxy) }
    }

    private func panelContent(proxy: ScrollViewProxy) -> some View {
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

            if showingSettingInfo {
                SettingInfoDisclosure(entries: infoEntries)
                    .id(Self.settingInfoID)
            }
        }
        // A settings panel changes; it doesn't perform. Rows that come and go with a
        // tracking mode appear where they belong rather than sliding or fading into
        // place. (The section panel drops this: its rest row *should* be seen arriving.)
        .transaction { $0.animation = nil }
        // Scrolled into view the moment it appears, rather than left for the user to
        // find below the fold — the panel can already be near its max height before
        // Setting Info even opens. Posted to the next runloop tick: the row has to
        // exist (this `if` has to have already re-rendered) before `scrollTo` can find
        // its id.
        .onChange(of: showingSettingInfo) { _, isShowing in
            guard isShowing else { return }
            DispatchQueue.main.async {
                withAnimation { proxy.scrollTo(Self.settingInfoID, anchor: .bottom) }
            }
        }
    }

    private static let settingInfoID = "settingInfo"

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
                if step.exercise?.weightedEquipmentOptions.isEmpty == false {
                    entries.append(SettingInfoEntry("Weight", "What this prefills at afterward when there's no personal record yet to use instead."))
                }
                entries.append(SettingInfoEntry("Color", "The accent color this step's card shows during the workout."))
            }
            return entries

        case .repEntry(let entry):
            // Ordered to match the rows themselves: Equipment/Weight read last here
            // too, as the closing "what this loads with" group.
            var entries: [SettingInfoEntry] = [
                SettingInfoEntry("Sets", "How many sets of this exercise the section calls for."),
                SettingInfoEntry("Rest Timer", "How long to rest between sets."),
                SettingInfoEntry("Track", "Whether sets are logged as reps and weight, or as how long you can hold it.")
            ]
            if entry.trackingMode == .maxHoldTime {
                entries.append(SettingInfoEntry("Prep", "A head start before the hold timer starts counting."))
            }
            if entry.exercise?.isOneSided == true, entry.trackingMode == .repsWeight {
                entries.append(SettingInfoEntry("Track L/R", "Logs the left and right sides as separate sets instead of one."))
            }
            if !(entry.exercise?.sortedExecutionTypes.isEmpty ?? true) {
                entries.append(SettingInfoEntry("Execution", "How the exercise is performed, when it has more than one style to choose from."))
                entries.append(SettingInfoEntry("Execution Editable", "Off fixes this entry's execution type for the whole workout — the runner can't change it mid-session."))
            }
            if entry.exercise?.progressionGroup != nil {
                entries.append(SettingInfoEntry("Progression", "Steps this exercise up or down its difficulty ladder automatically."))
            }
            if entry.exercise?.allowsBodyweight == true {
                entries.append(SettingInfoEntry("Bodyweight", "Lets this exercise's stepper offer an unloaded, bodyweight-only option."))
            }
            // Always shown now — a fixed single source or "No Equipment" is still
            // worth explaining, not just a real choice between several.
            entries.append(SettingInfoEntry("Equipment", "What this exercise is loaded with — a specific piece of equipment, or bodyweight."))
            if (entry.exercise?.weightedEquipmentOptions.count ?? 0) > 1 {
                entries.append(SettingInfoEntry("Equipment Editable", "Off fixes this entry's equipment for the whole workout — the runner can't change it mid-session. Doesn't affect Bodyweight, which Bodyweight on/off governs on its own."))
            }
            // Always shown too — Starting Reps is still functional with no weighted
            // equipment at all, even though Weight itself just reads "Bodyweight" then.
            entries.append(SettingInfoEntry("Weight", "What a fresh set opens prefilled at — used only if no personal record is available yet."))
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
            // Gray, to the left of Clone — same icon+caption shape as Clone/Delete,
            // just a quiet color rather than accent/danger, since it opens a glossary
            // rather than acting on the exercise.
            actionButton("info.circle", "Setting Info", tint: Color.appInkMuted) {
                showingSettingInfo.toggle()
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

/// `SettingStepper`'s weight counterpart — a starting-weight setting, stepped and
/// entered exactly the way a live set's own weight is.
///
/// Reuses the same primitives `SetRowView`'s weight control does rather than
/// reimplementing them: `steppedSetWeight` for the ± ladder, `WeightWheelPicker` for a
/// manual value outside it, `formattedSetWeight`/`formattedSetOption` for display. This
/// is not that control itself — `SetRowView`'s is entangled with live-session-only state
/// (`isLogged`, prominent sizing) a build-time settings row has no use for — just the
/// same interaction, so setting a starting weight here feels identical to adjusting one
/// mid-set. Always steps as a plain load: `isBodyweight`/`allowsBodyweight` are never
/// involved, since a starting weight has no bodyweight state of its own.
struct SettingWeightStepper: View {
    let title: String
    var columnWidth: CGFloat = SettingMetrics.repStepperLabelColumn
    @Binding var weight: Double
    let equipment: Equipment?
    let unit: String

    @State private var showingWheel = false

    private var options: [WeightCombo] { equipment?.sortedWeightCombos ?? [] }
    private var usesOptions: Bool { equipment?.usesOptions ?? false }

    var body: some View {
        HStack(spacing: SettingMetrics.rowSpacing) {
            Text("\(title):")
                .font(.subheadline)
                .foregroundStyle(Color.appInk)
                .frame(width: columnWidth, alignment: .leading)
                .minimumScaleFactor(0.75)

            RepeatingStepButton(systemImage: "minus.circle", isDisabled: false) { step(-1) }

            if usesOptions {
                Text(formattedSetOption(weight, options: options))
                    .font(.subheadline)
                    .foregroundStyle(Color.appRust)
                    .frame(minWidth: 40)
                    .minimumScaleFactor(0.75)
            } else {
                Button {
                    showingWheel = true
                } label: {
                    Text(formattedSetWeight(weight, unit: unit))
                        .font(.subheadline)
                        .foregroundStyle(Color.appRust)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 40)
                .minimumScaleFactor(0.75)
            }

            RepeatingStepButton(systemImage: "plus.circle", isDisabled: false) { step(1) }

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingWheel) {
            NavigationStack {
                VStack {
                    WeightWheelPicker(value: $weight, unit: unit).padding()
                    Spacer()
                }
                .background(Color.appBackground)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingWheel = false }
                    }
                }
            }
            .presentationDetents([.height(280)])
        }
    }

    private func step(_ delta: Int) {
        // `allowsBodyweight: false` means `.offerBodyweight` can never come back here.
        guard case .weight(let value, _) = steppedSetWeight(
            delta: delta, weight: weight, isBodyweight: false,
            options: options, allowsBodyweight: false
        ) else { return }
        weight = value
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

/// A hairline split by centered caption text — separates a settings row group (an
/// exercise's own capabilities, say) from another (what it's actually loaded with).
/// File-scoped rather than owned by one row type, since both `RepEntrySettingsRows`
/// and `TimeStepSettingsRows` use it.
private func labeledDivider(_ text: String) -> some View {
    HStack(spacing: 8) {
        Rectangle().fill(Color.appHairline).frame(height: 0.5)
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.appInkMuted)
            .fixedSize()
        Rectangle().fill(Color.appHairline).frame(height: 0.5)
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

    /// The step's own choice, else the exercise's default — mirrors
    /// `RepEntrySettingsRows.resolvedEquipment`.
    private var resolvedEquipment: Equipment? {
        step.preferredEquipment ?? step.exercise?.defaultWeightedEquipment
    }

    /// Same nil-coalescing idiom `RepEntrySettingsRows.startingWeightBinding` uses.
    private var startingWeightBinding: Binding<Double> {
        Binding(
            get: { step.startingWeight ?? (resolvedEquipment?.sortedWeightCombos.first?.value ?? 0) },
            set: { step.startingWeight = $0; save() }
        )
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

            // Not last anymore — the swatch strip still needs 246pt and so can't sit
            // beside the label column, but what this step is loaded with now closes the
            // panel out below it, the same "own capabilities, then what it loads with"
            // split `RepEntrySettingsRows` uses.
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

            labeledDivider("Equipment settings")

            // What the step is loaded with. Same picker the rep entry uses, and the same
            // reason it matters here: naming the equipment is what lets a held weight be
            // recorded at the end of the workout.
            EquipmentSourcePicker(step: step, context: context)

            // What the post-session record card prefills at when there's no personal
            // record yet — the Follow Along counterpart to a rep entry's own Weight,
            // minus a reps column: a held step has no rep count to seed.
            if step.exercise?.weightedEquipmentOptions.isEmpty == false {
                SettingWeightStepper(
                    title: "Weight",
                    columnWidth: SettingMetrics.labelColumn,
                    weight: startingWeightBinding,
                    equipment: resolvedEquipment,
                    unit: resolvedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit
                )
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

    /// The entry's own choice, else the exercise's default — the same resolution
    /// `EquipmentSourcePicker.resolvedSourceName` performs, so Starting Weight steps
    /// through the exact ladder this entry will actually be loaded with.
    private var resolvedEquipment: Equipment? {
        entry.preferredEquipment ?? entry.exercise?.defaultWeightedEquipment
    }

    /// Same three-way resolution `RepSessionRunnerView.weightSource` performs, minus
    /// its session-only override tier (there is no live session in the builder).
    private var isBodyweightSource: Bool {
        entry.prefersBodyweight || resolvedEquipment == nil
    }

    /// `resolvedEquipment` revalidated against this exercise's actual options — mirrors
    /// `RepSessionRunnerView.chosenEquipment`'s own fallback, so a stale/detached
    /// `preferredEquipment` still resolves to the record `chosenEquipment` would find.
    private var recordEquipment: Equipment? {
        guard !isBodyweightSource, let exercise = entry.exercise else { return nil }
        let options = exercise.weightedEquipmentOptions
        return options.first { $0.id == resolvedEquipment?.id } ?? options.first
    }

    /// The record this entry would seed from — `RepSessionRunnerView.recordSeed`'s own
    /// lookup, minus its "last logged set" tier (`SetLogQueries.lastBestSet`), which
    /// only makes sense mid-session. Reads `entry.trackingMode`/`.executionType` live,
    /// so switching Rep/Max time or execution type immediately looks up the record
    /// that actually matches the new combination, rather than always the reps/weight one.
    private var matchingRecord: PersonalRecord? {
        guard let exercise = entry.exercise else { return nil }
        return PersonalRecordQueries.current(
            for: exercise,
            equipment: recordEquipment,
            executionType: PersonalRecordQueries.resolvedExecutionType(entry.executionType, for: exercise),
            trackingMode: entry.trackingMode,
            isBodyweight: isBodyweightSource,
            context: context
        )
    }

    /// Nil-coalescing, like `restBinding`: touching it is what commits a real override.
    /// Untouched, it prefers the matching personal record, then falls back to the
    /// equipment's lightest preset exactly as before records were considered here.
    private var startingWeightBinding: Binding<Double> {
        Binding(
            get: { entry.startingWeight ?? matchingRecord?.weight ?? (resolvedEquipment?.sortedWeightCombos.first?.value ?? 0) },
            set: { entry.startingWeight = $0; save() }
        )
    }

    /// Same preference order as `startingWeightBinding`; the `8` fallback matches
    /// `recordSeed`'s own hardcoded guess in `RepSessionRunnerView`, so an untouched,
    /// record-less Starting Reps behaves identically to today.
    private var startingRepsBinding: Binding<Int> {
        Binding(
            get: { entry.startingReps ?? matchingRecord?.reps ?? 8 },
            set: { entry.startingReps = $0; save() }
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
                title: "Rest Timer",
                value: "\(restBinding.wrappedValue)",
                unit: "s",
                columnWidth: SettingMetrics.compactLabelColumn,
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

        // Separates Sets/Rest Timer/track/Prep — this exercise's own timing — from its
        // capabilities below (Track L/R, Execution, Progression). Omitted entirely
        // when none of those three apply, rather than labeling an empty gap.
        if hasExerciseDetailRows {
            labeledDivider("Exercise detail")
        }

        if entry.exercise?.isOneSided == true, entry.trackingMode == .repsWeight {
            SettingCell(title: "Track L/R", value: entry.tracksSides ? "on" : "off") {
                entry.tracksSides.toggle()
                save()
            }
        }

        // The workout's default. The runner can still override it in the moment, right up
        // until the first set is logged — unless Editable is off, which fixes it there
        // for the whole session instead.
        if !(entry.exercise?.sortedExecutionTypes.isEmpty ?? true) {
            HStack(spacing: SettingMetrics.pairSpacing) {
                ExecutionTypePicker(
                    options: entry.exercise?.sortedExecutionTypes ?? [],
                    selection: Binding(
                        get: { entry.executionType },
                        set: { entry.executionType = $0; save() }
                    )
                )
                .frame(width: halfColumn)

                SettingCell(title: "Editable", value: entry.executionTypeEditable ? "on" : "off") {
                    entry.executionTypeEditable.toggle()
                    save()
                }
                .frame(width: halfColumn)
            }
        }

        if entry.exercise?.progressionGroup != nil {
            SettingCell(title: "Progression", value: entry.progressionEnabled ? "on" : "off") {
                entry.progressionEnabled.toggle()
                save()
            }
        }

        // What this entry is loaded with, and where a fresh set starts from — closing
        // the panel out as one group, separate from the exercise's own capabilities above.
        labeledDivider("Equipment settings")

        // Distinct from the catalog's "Allow bodyweight", which lives on the exercise
        // page: that one says the exercise *can* be done unloaded, this one says this
        // workout offers the Body position on its stepper. The catalog flag is what
        // unlocks it, which is why the row only appears once it's set. Grouped with
        // Equipment below rather than the exercise's own capabilities above it, since
        // this is itself part of what the entry loads with.
        if entry.exercise?.allowsBodyweight == true {
            SettingCell(title: "Bodyweight", value: entry.allowsBodyweight ? "on" : "off") {
                entry.allowsBodyweight.toggle()
                // Bodyweight stops being offered below the moment this turns off —
                // an active Bodyweight selection would otherwise sit on a source the
                // Equipment menu no longer lists, so it falls back to the exercise's
                // own default equipment instead, the same reset `EquipmentSourcePicker`
                // itself performs in the opposite direction when Bodyweight is chosen.
                if !entry.allowsBodyweight && entry.prefersBodyweight {
                    entry.prefersBodyweight = false
                    entry.preferredEquipment = nil
                }
                save()
            }
        }

        // Always rendered now — `alwaysVisible` reads as a plain "No Equipment"/
        // single-source label rather than vanishing when there's nothing to choose.
        // Editable governs only the runner's own equipment menu, never Bodyweight
        // itself — that's the toggle above's job alone. Only shown at all when there's
        // more than one weighted option to actually lock — a single fixed piece of
        // equipment (or none) has no real choice for Editable to restrict.
        HStack(spacing: SettingMetrics.pairSpacing) {
            EquipmentSourcePicker(entry: entry, context: context, alwaysVisible: true)
                .frame(width: halfColumn)

            if (entry.exercise?.weightedEquipmentOptions.count ?? 0) > 1 {
                SettingCell(title: "Editable", value: entry.equipmentEditable ? "on" : "off") {
                    entry.equipmentEditable.toggle()
                    save()
                }
                .frame(width: halfColumn)
            } else {
                Color.clear.frame(width: halfColumn)
            }
        }

        // What a fresh set of this exercise opens prefilled at: the matching personal
        // record when there is one, else the same "nothing else to go on" guess as
        // before records were considered here. Always shown, even with no weighted
        // equipment at all — Weight reads as plain "Bodyweight" text then (the same
        // non-interactive treatment `EquipmentSourcePicker`'s
        // `alwaysVisible` fallback uses for "nothing to pick here"), but Starting Reps
        // is exactly as functional as ever; an exercise with nothing to load is no
        // reason to hide what a fresh set's rep count opens at. Reps holds its column
        // rather than disappearing in max-hold mode, so switching equipment never
        // shifts where it sits.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: SettingMetrics.pairSpacing) {
                // Left at `SettingWeightStepper`'s own default `repStepperLabelColumn`
                // — the same narrow column Sets/Rest Timer/track/Prep all use for a
                // stepper sharing a halfColumn row. Widening it to match "Equipment:"
                // was tried, but unlike Equipment's row (whose value text can shrink to
                // fit), a stepper's two ± buttons and its value button's own 40pt
                // minimum can't shrink — the extra label width just overflowed the
                // halfColumn instead, pushing "Reps:" out of line with "Editable:"
                // above it.
                Group {
                    if isBodyweightSource {
                        // `SettingRowLabel` doesn't expand on its own — without this,
                        // the outer `.frame(width: halfColumn)` below centers its
                        // (narrower) intrinsic width instead of left-aligning it,
                        // unlike Equipment's own matching "nothing to pick" fallback
                        // in `EquipmentSourcePicker`, which already carries this same
                        // modifier for the same reason.
                        SettingRowLabel(title: "Weight", value: "Bodyweight")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SettingWeightStepper(
                            title: "Weight",
                            weight: startingWeightBinding,
                            equipment: resolvedEquipment,
                            unit: resolvedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit
                        )
                    }
                }
                .frame(width: halfColumn)

                startingRepsStepper
                    .frame(width: halfColumn)
                    .opacity(entry.trackingMode == .repsWeight ? 1 : 0)
                    .disabled(entry.trackingMode != .repsWeight)
                    .accessibilityHidden(entry.trackingMode != .repsWeight)
            }

            Text("Used only if no record is available")
                .font(.caption2)
                .foregroundStyle(Color.appInkMuted)
        }
        // Re-seeds from whatever record matches the new combination the moment any
        // of these four change — even overriding a manual value from before —
        // whenever one actually exists to replace it with.
        .onChange(of: entry.prefersBodyweight) { _, _ in resetStartingValuesToRecord() }
        .onChange(of: entry.preferredEquipment?.id) { _, _ in resetStartingValuesToRecord() }
        .onChange(of: entry.executionType?.id) { _, _ in resetStartingValuesToRecord() }
        .onChange(of: entry.trackingMode) { _, _ in resetStartingValuesToRecord() }
    }

    private var hasExerciseDetailRows: Bool {
        (entry.exercise?.isOneSided == true && entry.trackingMode == .repsWeight)
            || !(entry.exercise?.sortedExecutionTypes.isEmpty ?? true)
            || entry.exercise?.progressionGroup != nil
    }

    /// Only when a record actually exists for the new combination — otherwise a
    /// manual override with nothing to replace it with is left exactly as the
    /// builder set it.
    private func resetStartingValuesToRecord() {
        guard matchingRecord != nil else { return }
        entry.startingWeight = nil
        entry.startingReps = nil
        save()
    }

    /// Pulled out of `body` for the same reason `prepStepper` is — rendered in both
    /// tracking modes, visible in one and holding its space in the other.
    private var startingRepsStepper: some View {
        SettingStepper(
            title: "Reps",
            value: "\(startingRepsBinding.wrappedValue)",
            columnWidth: SettingMetrics.repStepperLabelColumn,
            range: 1...50,
            step: 1,
            number: startingRepsBinding
        )
    }

    /// Pulled out of `body` because it is rendered in both tracking modes — visible in one
    /// and holding its space in the other.
    private var prepStepper: some View {
        SettingStepper(
            title: "Prep",
            value: "\(entry.headStartSeconds)",
            unit: "s",
            columnWidth: SettingMetrics.compactLabelColumn,
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
