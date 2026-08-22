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

/// What the section is and everything it's set to, shown under its name. Every setting
/// stays listed whatever its value — an "off" that vanishes is indistinguishable from
/// a setting that doesn't apply, so `Autostart: off` and `Repeat: no` are spelled out.
func sectionSettingsSummary(_ section: WorkoutSection) -> String {
    var parts: [String] = [section.sectionType.pillLabel]

    let count = sectionExerciseCount(section)
    parts.append("\(count) Exercise\(count == 1 ? "" : "s")")

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
    var onClone: () -> Void
    var onDelete: () -> Void

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
    private var actionsRow: some View {
        HStack(spacing: 28) {
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
