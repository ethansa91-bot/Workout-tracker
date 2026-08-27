import SwiftUI
import SwiftData

/// A settings row reads "Label: value" on one line, so every setting and what it's
/// currently set to is visible without touching the control — the popover doubles as
/// a readout of the same summary shown under the section/exercise name.
struct SettingRowLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text("\(title):")
                .font(.subheadline)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.appRust)
        }
        .lineLimit(1)
    }
}

/// The section's get-ready step, which every `.time` section is guaranteed to have —
/// `WorkoutEditingService.addSection` creates one and `GetReadyStepMigration` backfills
/// older sections. It's a real step that the runner plays; it's just presented as a
/// section setting rather than as a row in the exercise list.
func getReadyStep(of section: WorkoutSection) -> TimeSectionStep? {
    guard section.sectionType == .time else { return nil }
    return section.sortedTimeSteps.first { $0.stepType == .getReady }
}

/// How many real exercises a section holds — Get Ready and Rest aren't exercises.
func sectionExerciseCount(_ section: WorkoutSection) -> Int {
    switch section.sectionType {
    case .time: return section.sortedTimeSteps.filter { $0.stepType == .exercise }.count
    case .rep: return section.sortedRepExercises.count
    case .emom, .amrap: return section.sortedQuickExercises.count
    }
}

/// What one set of a rep exercise is assumed to take. Rep sections are the only kind
/// with no stored duration — a set is however long you take over it — so an estimate
/// has to assume a figure, and this is it.
let estimatedRepSetSeconds = 45

/// Rough padding on the workout total for everything the section math can't see:
/// setup, plate changes, walking between stations, the pause between sections.
/// Applied once at the workout level so per-section estimates stay unpadded.
private let estimateOverheadFactor = 1.10

/// Roughly how long a section takes, including its repeats.
///
/// Exact for time/EMOM/AMRAP, which are driven end to end by stored durations. For a
/// rep section each set slot is assumed to take `estimatedRepSetSeconds` and rest is
/// added once per *set* rather than per slot: a two-sided exercise works both sides
/// between the same two rests, so its slots double but its rests do not.
func estimatedSectionSeconds(_ section: WorkoutSection) -> Int {
    let perPass: Int
    switch section.sectionType {
    case .time:
        // Every step carries a duration, Rest and Get Ready included, and the runner
        // plays them back to back with no gap — so the sum is the real elapsed time.
        perPass = section.sortedTimeSteps.reduce(0) { $0 + $1.durationSeconds }
    case .emom:
        // A round is always one minute; the count is the only variable.
        perPass = section.emomRoundCount * 60
    case .amrap:
        perPass = section.amrapDurationSeconds
    case .rep:
        perPass = section.sortedRepExercises.reduce(0) { total, entry in
            let rest = entry.customRestSeconds ?? AppSettings.defaultRestSeconds
            let work = estimatedRepSetSeconds * entry.totalSetSlots
            // The head start runs before each hold, so it scales with slots, not sets.
            let headStart = entry.trackingMode == .maxHoldTime
                ? entry.headStartSeconds * entry.totalSetSlots
                : 0
            return total + work + headStart + rest * entry.targetSets
        }
    }
    return perPass * section.effectiveRepeatCount
}

/// The whole workout's estimate — every section, repeats included, plus
/// `estimateOverheadFactor` for the between-section overhead the per-section math
/// can't account for.
func estimatedWorkoutSeconds(_ workout: Workout) -> Int {
    let base = workout.sortedSections.reduce(0) { $0 + estimatedSectionSeconds($1) }
    return Int((Double(base) * estimateOverheadFactor).rounded())
}

/// An estimate rendered for display: "~25 min", or "~1 h 05 min" once it passes an
/// hour. Always approximate, so it always carries the tilde.
func formattedEstimate(_ seconds: Int) -> String {
    let totalMinutes = max(1, Int((Double(seconds) / 60).rounded()))
    guard totalMinutes >= 60 else { return "~\(totalMinutes) min" }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return String(format: "~%d h %02d min", hours, minutes)
}

/// What kind of section it is and how much is in it — the two facts that identify it at
/// a glance, so they sit beside the name rather than in the settings line below.
func sectionKindSummary(_ section: WorkoutSection) -> String {
    let count = sectionExerciseCount(section)
    return "\(section.sectionType.pillLabel) · \(count) Exercise\(count == 1 ? "" : "s")"
}

/// Everything the section is *set to*, minus the kind and count `sectionKindSummary`
/// already carries. Every setting stays listed whatever its value — an "off" that
/// vanishes is indistinguishable from a setting that doesn't apply, so `Autostart: off`
/// and `Repeat: no` are spelled out.
func sectionSettingsSummary(_ section: WorkoutSection) -> String {
    var parts: [String] = []

    switch section.sectionType {
    case .emom:
        parts.append("Rounds: \(section.emomRoundCount) (\(section.emomRoundCount) min)")
    case .amrap:
        parts.append("Duration: \(section.amrapDurationSeconds / 60) min")
    case .time:
        if let getReady = getReadyStep(of: section) {
            parts.append("Get Ready: \(getReady.durationSeconds)s")
        }
    case .rep:
        break
    }

    // `.rep` sections ignore `autostart` entirely — there's no timer to start.
    if section.sectionType != .rep {
        parts.append("Autostart: \(section.autostart ? "on" : "off")")
    }

    parts.append("Repeat: \(section.effectiveRepeatCount > 1 ? "x\(section.effectiveRepeatCount)" : "no")")

    return parts.joined(separator: " · ")
}

/// Quick-adjust panel for a section's timing settings, shown as a glass popover
/// anchored to the gear button in the recap card's header. Every control writes
/// straight through `WorkoutEditingService` — which saves immediately and refuses
/// edits to a locked workout — so there's no Save button here.
struct SectionSettingsPopover: View {
    @Bindable var section: WorkoutSection
    let context: ModelContext
    var onError: (String) -> Void
    /// nil hides the action. A standalone template section has no siblings to be
    /// cloned or deleted among, so it passes nil for both and the row disappears.
    var onClone: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch section.sectionType {
            case .time:
                getReadyRow
                autostartRow
                repeatRow
            case .rep:
                repeatRow
            case .emom:
                emomRoundsRow
                autostartRow
                repeatRow
            case .amrap:
                amrapDurationRow
                autostartRow
                repeatRow
            }

            Divider()
            actionsRow
        }
        .padding(16)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }

    /// Same shape as the exercise popover's actions, so clone and delete live in the
    /// same place whichever level you're editing.
    @ViewBuilder
    private var actionsRow: some View {
        if onClone != nil || onDelete != nil {
            HStack(spacing: 28) {
                if let onClone {
                    actionButton("doc.on.doc", "Clone", tint: Color.appAccent, action: onClone)
                }
                if let onDelete {
                    actionButton("trash", "Delete", tint: Color.appDanger, action: onDelete)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
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

    // MARK: - Rows

    private var autostartRow: some View {
        Toggle(isOn: autostartBinding) {
            SettingRowLabel(title: "Autostart", value: section.autostart ? "on" : "off")
        }
        .tint(Color.appAccent)
    }

    private var repeatRow: some View {
        Stepper(value: repeatBinding, in: 1...20) {
            SettingRowLabel(title: "Repeat", value: section.effectiveRepeatCount > 1 ? "x\(section.effectiveRepeatCount)" : "no")
        }
    }

    /// Edits the section's real get-ready step in place. It stays a `TimeSectionStep`
    /// the runner plays — only its presentation moved here from the exercise list.
    @ViewBuilder
    private var getReadyRow: some View {
        if let step = getReadyStep(of: section) {
            Stepper(value: Binding(
                get: { step.durationSeconds },
                set: { newValue in
                    step.durationSeconds = newValue
                    step.markDirty()
                    try? context.save()
                }
            ), in: 0...300, step: 5) {
                SettingRowLabel(title: "Get Ready", value: "\(step.durationSeconds)s")
            }
        }
    }

    private var emomRoundsRow: some View {
        Stepper(value: emomRoundsBinding, in: 1...60) {
            SettingRowLabel(title: "Rounds", value: "\(section.emomRoundCount) (\(section.emomRoundCount) min)")
        }
    }

    private var amrapDurationRow: some View {
        Stepper(value: amrapMinutesBinding, in: 1...60) {
            SettingRowLabel(title: "Duration", value: "\(section.amrapDurationSeconds / 60) min")
        }
    }

    // MARK: - Bindings

    private var autostartBinding: Binding<Bool> {
        Binding(get: { section.autostart }, set: { newValue in update { try WorkoutEditingService.updateAutostart(section, to: newValue, context: context) } })
    }

    private var repeatBinding: Binding<Int> {
        Binding(get: { section.repeatCount }, set: { newValue in update { try WorkoutEditingService.updateRepeatCount(section, to: newValue, context: context) } })
    }

    private var emomRoundsBinding: Binding<Int> {
        Binding(get: { section.emomRoundCount }, set: { newValue in update { try WorkoutEditingService.updateEmomRoundCount(section, to: newValue, context: context) } })
    }

    private var amrapMinutesBinding: Binding<Int> {
        Binding(get: { section.amrapDurationSeconds / 60 }, set: { newValue in update { try WorkoutEditingService.updateAmrapDuration(section, to: newValue * 60, context: context) } })
    }

    private func update(_ work: () throws -> Void) {
        do { try work() }
        catch { onError(error.localizedDescription) }
    }
}
