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
/// actually allows them for, matching the conditionals that gate the popover's rows —
/// an option that can't be turned on is noise, not information.
func exerciseSettingsSummary(_ target: ExerciseSettingsTarget) -> String? {
    var parts: [String] = []

    switch target {
    case .timeStep(let step):
        parts.append("\(step.durationSeconds)s")
        if step.stepType == .exercise {
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
                parts.append("Bodyweight: \(entry.allowsBodyweight ? "on" : "off")")
            }
            if entry.exercise?.isOneSided == true {
                parts.append("L/R: \(entry.tracksSides ? "on" : "off")")
            }
            if let equipment = entry.preferredEquipment {
                parts.append("Equipment: \(equipment.name)")
            }
        case .maxHoldTime:
            parts.append("Track: max time")
            parts.append("Head start: \(entry.headStartSeconds)s")
        }

    case .quickEntry:
        // Nothing to configure — these rows show no summary line at all.
        break
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// Quick-adjust panel for a single exercise, shown as a glass popover anchored to the
/// gear on its row. Same immediate-save behavior as the section editors' inline
/// accordions this replaces — every field writes straight through on change.
struct ExerciseSettingsPopover: View {
    let target: ExerciseSettingsTarget
    let context: ModelContext
    var onClone: () -> Void
    var onDelete: () -> Void
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

    /// Quick entries have no settings of their own, so their popover is actions only —
    /// no divider floating above an empty list.
    private var hasSettings: Bool {
        if case .quickEntry = target { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch target {
            case .timeStep(let step):
                TimeStepSettingsRows(step: step, context: context)
            case .repEntry(let entry):
                RepEntrySettingsRows(entry: entry, context: context)
            case .quickEntry:
                EmptyView()
            }

            if hasSettings {
                Divider()
            }
            actionsRow
        }
        .padding(16)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }

    private var actionsRow: some View {
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
        Stepper(value: Binding(
            get: { step.durationSeconds },
            set: { step.durationSeconds = $0; save() }
        ), in: durationRange, step: 5) {
            SettingRowLabel(title: "Duration", value: "\(step.durationSeconds)s")
        }

        // Rest and Get Ready stay plain gray in the lists — no color to pick.
        if step.stepType == .exercise {
            VStack(alignment: .leading, spacing: 8) {
                SettingRowLabel(title: "Color", value: step.resolvedColor.label)
                // 8 swatches at the default 28pt overflow the popover's width, so this
                // uses the picker's existing size knob rather than widening the panel.
                PaletteColorPicker(selection: Binding(
                    get: { step.color },
                    set: { step.color = $0; save() }
                ), swatchSize: 22, defaultSelection: step.resolvedColor)
            }
        }
    }

    private func save() {
        step.markDirty()
        try? context.save()
    }
}

// MARK: - Rep exercises

private struct RepEntrySettingsRows: View {
    @Bindable var entry: RepSectionExercise
    let context: ModelContext

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
        Stepper(value: Binding(
            get: { entry.targetSets },
            set: { entry.targetSets = $0; save() }
        ), in: 1...20) {
            SettingRowLabel(title: "Sets", value: "\(entry.targetSets)")
        }

        Stepper(value: restBinding, in: 0...600, step: 15) {
            SettingRowLabel(title: "Rest", value: "\(restBinding.wrappedValue)s")
        }

        VStack(alignment: .leading, spacing: 6) {
            SettingRowLabel(
                title: "Track by",
                value: entry.trackingMode == .repsWeight ? "reps & weight" : "max time"
            )
            Picker("Track by", selection: Binding(
                get: { entry.trackingMode },
                set: { entry.trackingMode = $0; save() }
            )) {
                Text("Reps & Weight").tag(RepExerciseTrackingMode.repsWeight)
                Text("Max Time").tag(RepExerciseTrackingMode.maxHoldTime)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        if entry.trackingMode == .maxHoldTime {
            Stepper(value: Binding(
                get: { entry.headStartSeconds },
                set: { entry.headStartSeconds = $0; save() }
            ), in: 0...30) {
                SettingRowLabel(title: "Head start", value: "\(entry.headStartSeconds)s")
            }
        }

        // Both are offered only for exercises flagged for them in the catalog —
        // marking an exercise there is what makes the option meaningful here.
        if entry.exercise?.allowsBodyweight == true {
            Toggle(isOn: Binding(
                get: { entry.allowsBodyweight },
                set: { entry.allowsBodyweight = $0; save() }
            )) {
                SettingRowLabel(title: "Bodyweight", value: entry.allowsBodyweight ? "on" : "off")
            }
            .tint(Color.appAccent)
        }

        if entry.exercise?.isOneSided == true, entry.trackingMode == .repsWeight {
            Toggle(isOn: Binding(
                get: { entry.tracksSides },
                set: { entry.tracksSides = $0; save() }
            )) {
                SettingRowLabel(title: "Track L/R", value: entry.tracksSides ? "on" : "off")
            }
            .tint(Color.appAccent)
        }

        // Offered in both tracking modes: a max-time hold can be loaded too (a weighted
        // plank), and bodyweight is one of the choices rather than a separate toggle.
        EquipmentSourcePicker(entry: entry, context: context)
    }

    private func save() {
        entry.markDirty()
        try? context.save()
    }
}
