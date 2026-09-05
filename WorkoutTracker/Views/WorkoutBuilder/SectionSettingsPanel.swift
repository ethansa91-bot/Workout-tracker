import SwiftUI
import SwiftData
import UIKit

/// A settings row reads "Label: value" on one line, so every setting and what it's
/// currently set to is visible without touching the control — the panel doubles as
/// a readout of the same summary shown under the section/exercise name.
/// The shared geometry that makes a panel read as one column rather than as a stack of
/// independently-sized rows.
enum SettingMetrics {
    /// Reserved for the title in a row that isn't squeezed for space — every
    /// `SettingCell`/`SettingMenu` row (Autostart, Track record, Bodyweight, Execution,
    /// Progression...), and a `SettingStepper` with a full line to itself (Duration,
    /// Reps). Sized for the longest label either panel ever shows ("Track record:",
    /// "Progression:") so every value in that kind of row starts at one x — with room
    /// left over even in a half-width column, since none of these carry the ± buttons a
    /// stepper does.
    static var labelColumn: CGFloat {
        UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 100)
    }

    /// Reserved for the title in a `SettingStepper`/`SettingMenu` that shares its line
    /// with another setting, or otherwise lives in a half-width column — Get Ready, Rest,
    /// Rounds, Repeat. Narrower than `labelColumn` on purpose: a stepper's ± buttons and
    /// value already claim most of a half column, and reserving the full label width
    /// there is what left "Section rest:" truncating to "...est:" with nowhere for its
    /// value to go. Sized for the longest title that ever appears this way, "Get Ready:".
    static var compactLabelColumn: CGFloat {
        UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 68)
    }

    /// The rep-exercise panel's own compact rows — Sets, Rest, track, Prep — about 20%
    /// narrower than `compactLabelColumn`. All four labels are shorter than "Get Ready:",
    /// the longest title `compactLabelColumn` has to fit, so this group can give back a
    /// bit more of its half column to the value and ± buttons without losing anything.
    static var repStepperLabelColumn: CGFloat {
        UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 54)
    }

    /// Between the title column and whatever follows it. Shared so `SettingStepper`'s
    /// hand-built row and `SettingRowLabel` can't drift apart.
    static let rowSpacing: CGFloat = 4

    static let panelPadding: CGFloat = 16
    /// Between the two halves of a paired row.
    static let pairSpacing: CGFloat = 8

    /// The width a panel's content had back when both were fixed-size popovers, kept as
    /// the fallback for the first render — before `SettingsPanelSheet` has measured the
    /// real one, which is a whole screen wider on a phone.
    static let fallbackContentWidth: CGFloat = 300 - panelPadding * 2

    /// Half of a paired row, computed rather than left to the layout.
    ///
    /// `SettingStepper` and `SettingMenu` both carry `maxWidth: .infinity`, so an `HStack`
    /// of two of them divides itself by their relative flexibility — a menu beside a
    /// stepper does not land on the same split as two steppers, which is why Prep and Rest
    /// disagreed. A fixed width takes the question away — which is why this takes the
    /// measured width rather than the panel becoming flexible now that it can be any width.
    static func halfColumn(for contentWidth: CGFloat) -> CGFloat {
        let width = contentWidth > 0 ? contentWidth : fallbackContentWidth
        return (width - pairSpacing) / 2
    }

    /// What a panel opens at before it has measured itself. Small enough that the first
    /// frame never overshoots and shrinks back.
    static let fallbackPanelHeight: CGFloat = 240

    /// A panel opens exactly as tall as its rows, up to half the screen — no dead space
    /// under a short one, and the tallest still leaves the section it belongs to visible
    /// behind it. Past this it scrolls, or is dragged up to full height.
    static var maxOpenPanelHeight: CGFloat {
        // `UIScreen.main` is soft-deprecated; the active scene's screen is the same value
        // and survives on iPad, where the app can be in a resized window.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let height = scene?.screen.bounds.height ?? UIScreen.main.bounds.height
        return (height * 0.5).rounded()
    }
}

/// A row that isn't sharing its line, sized to the first column.
///
/// Not full width: a control flush against the panel's right edge would sit far from the
/// first column's controls, and the alignment only means anything if a single row's value
/// lands where a paired row's left half puts its own.
extension View {
    func settingColumn(_ contentWidth: CGFloat) -> some View {
        frame(width: SettingMetrics.halfColumn(for: contentWidth), alignment: .leading)
    }
}

/// Two rows sharing a line, each in its own equal-width column.
///
/// Fixed halves rather than a flexible `HStack`: `SettingStepper` and `SettingMenu` both
/// carry `maxWidth: .infinity`, so left to itself the row divides by relative flexibility —
/// a menu beside a stepper lands on a different split than two steppers, which is why Prep
/// and Rest used to disagree.
///
/// A half whose row has hidden itself is simply empty. The other half keeps exactly the
/// width and position it would have had, so nothing slides sideways when a setting that
/// no longer applies drops out.
struct SettingPairRow<Leading: View, Trailing: View>: View {
    /// The panel's measured content width — see `SettingsPanelSheet`.
    let contentWidth: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: SettingMetrics.pairSpacing) {
            leading.frame(width: SettingMetrics.halfColumn(for: contentWidth), alignment: .leading)
            trailing.frame(width: SettingMetrics.halfColumn(for: contentWidth), alignment: .leading)
        }
    }
}

/// The chrome both settings panels share as a bottom sheet.
///
/// They were fixed 300pt popovers anchored to the gear that opened them, which is why the
/// paired rows carried hard-coded half-widths and the colour swatches were shrunk to fit.
/// A sheet has the screen's width and no anchor, so the panel measures itself instead: the
/// height drives the detent, and the width is handed back so the paired rows can split
/// what's actually there.
struct SettingsPanelSheet<Content: View>: View {
    /// The content's measured size. A binding rather than internal state because the
    /// content itself needs the width to lay its paired rows out.
    @Binding var contentSize: CGSize
    @ViewBuilder var content: Content

    private var fittedHeight: CGFloat {
        let measured = contentSize.height + SettingMetrics.panelPadding * 2
        guard measured > 0 else { return SettingMetrics.fallbackPanelHeight }
        return min(measured, SettingMetrics.maxOpenPanelHeight)
    }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
                .padding(SettingMetrics.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No `selection:`, so the sheet always opens at the fitted height and follows it
        // when a row appears — binding a selection would pin it to a stale height the
        // moment the content grew.
        .presentationDetents([.height(fittedHeight), .large])
        .presentationBackground(.ultraThinMaterial)
    }
}

/// One line in a panel's built-in glossary: a setting's name, and in one short sentence,
/// what it actually does — plain enough that someone who has never opened this app before
/// can tell what they'd be changing.
struct SettingInfoEntry: Identifiable {
    let id = UUID()
    let name: String
    let explanation: String

    init(_ name: String, _ explanation: String) {
        self.name = name
        self.explanation = explanation
    }
}

/// A quiet way in to "what does this do", below everything else in the panel and
/// collapsed until tapped — so it never competes with the settings themselves, and
/// someone who already knows what Autostart does never has to look at it.
///
/// `entries` is built by the panel from the exact same conditions that choose which rows
/// to show, so the glossary only ever explains what's actually on screen right now — not
/// a fixed list of every setting either panel could ever have.
struct SettingInfoDisclosure: View {
    let entries: [SettingInfoEntry]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Setting info")
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appInk)
                            Text(entry.explanation)
                                .font(.caption2)
                                .foregroundStyle(Color.appInkMuted)
                        }
                    }
                }
            }
        }
    }
}

struct SettingRowLabel: View {
    let title: String
    let value: String
    /// Drops the reserved column and lets the title take its own natural width instead —
    /// for a row standing on its own outside a panel, where there is nothing to line up
    /// with and a reserved column would only stretch the gap before the value. Wins over
    /// `columnWidth` when both are set.
    var hugsTitle: Bool = false
    /// Which fixed column to reserve for the title, when not hugging. Defaults to
    /// `SettingMetrics.labelColumn` — the room-to-spare width every `SettingCell`/
    /// `SettingMenu` row uses, since none of them carry a stepper's ± buttons even in a
    /// half-width slot. A caller that has to line up with a squeezed `SettingStepper`
    /// instead — "track", under Sets — passes `SettingMetrics.compactLabelColumn` or
    /// `.repStepperLabelColumn`, the same values that stepper itself uses.
    var columnWidth: CGFloat = SettingMetrics.labelColumn
    /// Rust in the panels. Overridden where the row belongs to a section with its own
    /// colour family — the exercise page's Default equipment row takes the blue its
    /// Weighted Equipment chips already use.
    var valueColor: Color = .appRust

    private var resolvedWidth: CGFloat? { hugsTitle ? nil : columnWidth }

    var body: some View {
        HStack(spacing: hugsTitle ? 4 : SettingMetrics.rowSpacing) {
            Text("\(title):")
                .font(.subheadline)
                // Explicit, not inherited: a row that tinted itself to colour a button
                // used to drag the label along with it.
                .foregroundStyle(Color.appInk)
                // The shared column, so every row of the same kind starts its value at
                // the same x — that's what "aligned" means for a panel with more than one
                // row.
                .frame(width: resolvedWidth, alignment: .leading)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                // Scales instead of truncating: a half-width row carries values as long as
                // "Reps and weights", and an equipment name has no length limit at all.
                .minimumScaleFactor(0.75)
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
    let passes = section.effectiveRepeatCount
    // No longer a flat `perPass * passes`: a count-in that doesn't repeat makes the first
    // pass longer than the rest, so every pass is measured on its own. The section rest
    // sits *between* passes, which is why it is counted `passes - 1` times.
    let work = (0..<passes).reduce(0) { $0 + passSeconds(section, pass: $1) }
    return work + section.sectionRestSeconds * max(0, passes - 1)
}

/// One pass through a section, in seconds.
private func passSeconds(_ section: WorkoutSection, pass: Int) -> Int {
    switch section.sectionType {
    case .time:
        // Every step carries a duration, Rest and Get Ready included, and the runner
        // plays them back to back with no gap — so the sum is the real elapsed time.
        return section.runnableTimeSteps(pass: pass).reduce(0) { $0 + $1.durationSeconds }
    case .emom:
        // An open-ended section has no length to estimate — only the count-in is known.
        // The workout total will under-report it, which is the honest answer: how long it
        // runs is exactly the thing the user is trying to find out.
        guard !section.emomToFailure else { return section.countInSeconds(pass: pass) }
        // A round is always one minute; the count is the only variable.
        return section.countInSeconds(pass: pass) + section.emomRoundCount * 60
    case .amrap:
        return section.countInSeconds(pass: pass) + section.amrapDurationSeconds
    case .rep:
        return section.sortedRepExercises.reduce(0) { total, entry in
            let rest = entry.customRestSeconds ?? AppSettings.defaultRestSeconds
            let work = estimatedRepSetSeconds * entry.totalSetSlots
            // The head start runs before each hold, so it scales with slots, not sets.
            let headStart = entry.trackingMode == .maxHoldTime
                ? entry.headStartSeconds * entry.totalSetSlots
                : 0
            return total + work + headStart + rest * entry.targetSets
        }
    }
}

/// The whole workout's estimate — every section, repeats included, plus
/// `estimateOverheadFactor` for the between-section overhead the per-section math
/// can't account for.
func estimatedWorkoutSeconds(_ workout: Workout) -> Int {
    let base = workout.sortedSections.reduce(0) { $0 + estimatedSectionSeconds($1) }
    return Int((Double(base) * estimateOverheadFactor).rounded())
}

/// A section's estimate as it should be shown, or nil when there isn't one to show.
///
/// An open-ended EMOM has no length: `estimatedSectionSeconds` returns just its count-in,
/// which would render as a confident "~1 min" for a section that could run twenty. How
/// long it lasts is exactly what the user is trying to find out, so the honest answer is
/// to say so rather than to guess.
func formattedSectionEstimate(_ section: WorkoutSection) -> String {
    guard !section.isToFailure else { return "open-ended" }
    return formattedEstimate(estimatedSectionSeconds(section))
}

/// Whether any part of the workout runs for an unknown length, which makes the total a
/// floor rather than an estimate.
func hasOpenEndedSection(_ workout: Workout) -> Bool {
    workout.sortedSections.contains { $0.isToFailure }
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
        if section.emomToFailure {
            parts.append("Rounds: to failure")
        } else {
            parts.append("Rounds: \(section.emomRoundCount) (\(section.emomRoundCount) min)")
        }
        if section.getReadySeconds > 0 {
            parts.append("Get Ready: \(section.getReadySeconds)s")
        }
        if section.tracksRecord { parts.append("Record: on") }
    case .amrap:
        parts.append("Duration: \(section.amrapDurationSeconds / 60) min")
        if section.getReadySeconds > 0 {
            parts.append("Get Ready: \(section.getReadySeconds)s")
        }
        if section.tracksRecord { parts.append("Record: on") }
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

    if section.effectiveRepeatCount > 1, section.sectionType != .rep {
        if section.sectionRestSeconds > 0 {
            parts.append("Section rest: \(section.sectionRestSeconds)s")
        }
        if !section.repeatsGetReadyEachPass {
            parts.append("Get Ready: first pass only")
        }
    }

    return parts.joined(separator: " · ")
}

/// Quick-adjust panel for a section's timing settings, shown as a glass sheet
/// anchored to the gear button in the recap card's header. Every control writes
/// straight through `WorkoutEditingService` — which saves immediately and refuses
/// edits to a locked workout — so there's no Save button here.
struct SectionSettingsPanel: View {
    @Bindable var section: WorkoutSection
    let context: ModelContext
    var onError: (String) -> Void
    /// nil hides the action. A standalone template section has no siblings to be
    /// cloned or deleted among, so it passes nil for both and the row disappears.
    var onClone: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Measured by `SettingsPanelSheet`; `getReadyPairRow` splits the width.
    @State private var contentSize: CGSize = .zero

    var body: some View {
        SettingsPanelSheet(contentSize: $contentSize) { panelContent }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleRow
            Divider()

            // Everything that defines the work is inert once a record has been set
            // against the section — changing it would change what the record means.
            // `trackRecordRow` sits outside, because turning tracking off is the way back
            // out of that lock and has to stay reachable.
            // The three types share a shape: what runs it first, then the count-in and
            // whether it repeats, then the passes and the rest between them — each of the
            // last two pairs being one question asked in two halves.
            Group {
                switch section.sectionType {
                case .time:
                    autostartRow.settingColumn(contentSize.width)
                    getReadyPairRow
                    repeatPairRow
                case .rep:
                    repeatRow.settingColumn(contentSize.width)
                case .emom:
                    autostartRow.settingColumn(contentSize.width)
                    // Paired rather than two rows apart: turning rounds open-ended is
                    // what makes a record possible at all, so the toggle and what it
                    // unlocks read as one control instead of two that happen to be near
                    // each other. The right half is simply blank until To failure is on
                    // — `trackRecordRow` still gates itself on `canTrackRecord`.
                    toFailureTrackRecordPairRow
                    quickGetReadyPairRow
                    // No slot at all once open-ended: a fixed EMOM has rounds to set, and
                    // an open-ended one has nothing left to — the record it can move is
                    // already offered above, beside the toggle that unlocked it.
                    if !section.emomToFailure {
                        emomRoundsRow.settingColumn(contentSize.width)
                    }
                    // A to-failure section is always one pass, so the repeat pair has
                    // nothing to act on.
                    if !section.emomToFailure {
                        repeatPairRow
                    }
                case .amrap:
                    autostartRow.settingColumn(contentSize.width)
                    amrapDurationRow.settingColumn(contentSize.width)
                    repeatPairRow
                    quickGetReadyPairRow
                    trackRecordRow.settingColumn(contentSize.width)
                }
            }
            .disabled(isRecordLocked)
            .opacity(isRecordLocked ? 0.5 : 1)

            actionsRow

            SettingInfoDisclosure(entries: infoEntries)
        }
        // A settings panel changes; it doesn't perform. A row that stops applying — Section
        // rest once the repeat count drops back to 1, Rounds once an EMOM goes open-ended —
        // is simply not there next time you look, rather than sliding or fading away. This
        // also holds the sheet's own height still while the content behind it changes.
        .transaction { $0.animation = nil }
    }

    /// Mirrors exactly the conditions `panelContent`'s switch uses to choose its rows, so
    /// the glossary below never names a setting that isn't actually showing above it.
    private var infoEntries: [SettingInfoEntry] {
        var entries: [SettingInfoEntry] = []
        switch section.sectionType {
        case .time:
            entries.append(SettingInfoEntry("Autostart", "Starts this section's timer the moment the workout reaches it, instead of waiting for a tap."))
            if getReadyStep(of: section) != nil {
                entries.append(SettingInfoEntry("Get Ready", "A countdown before the first exercise begins."))
                if section.effectiveRepeatCount > 1, hasCountIn {
                    entries.append(SettingInfoEntry("Repeated", "Plays the Get Ready countdown again on every repeat pass, not just the first."))
                }
            }
            entries.append(SettingInfoEntry("Repeat", "How many times this section's exercises run through, back to back."))
            if section.effectiveRepeatCount > 1 {
                entries.append(SettingInfoEntry("Rest", "A break between one repeat pass and the next."))
            }
        case .rep:
            entries.append(SettingInfoEntry("Repeat", "How many times this section's exercises run through, back to back."))
        case .emom:
            entries.append(SettingInfoEntry("Autostart", "Starts this section's timer the moment the workout reaches it, instead of waiting for a tap."))
            entries.append(SettingInfoEntry("To failure", "Runs rounds until you stop them yourself, instead of ending at a set number."))
            if section.canTrackRecord {
                entries.append(SettingInfoEntry("Track record", "Saves your best round count here as a personal record."))
            }
            entries.append(SettingInfoEntry("Get Ready", "A countdown before the first round begins."))
            if section.effectiveRepeatCount > 1, hasCountIn {
                entries.append(SettingInfoEntry("Repeated", "Plays the Get Ready countdown again on every repeat pass, not just the first."))
            }
            if !section.emomToFailure {
                entries.append(SettingInfoEntry("Rounds", "How many one-minute rounds this section runs."))
            }
            if !section.emomToFailure {
                entries.append(SettingInfoEntry("Repeat", "How many times this section runs through, back to back."))
                if section.effectiveRepeatCount > 1 {
                    entries.append(SettingInfoEntry("Rest", "A break between one repeat pass and the next."))
                }
            }
        case .amrap:
            entries.append(SettingInfoEntry("Autostart", "Starts this section's timer the moment the workout reaches it, instead of waiting for a tap."))
            entries.append(SettingInfoEntry("Duration", "How long this AMRAP round lasts."))
            entries.append(SettingInfoEntry("Repeat", "How many times this section runs through, back to back."))
            if section.effectiveRepeatCount > 1 {
                entries.append(SettingInfoEntry("Rest", "A break between one repeat pass and the next."))
            }
            entries.append(SettingInfoEntry("Get Ready", "A countdown before the round begins."))
            if section.effectiveRepeatCount > 1, hasCountIn {
                entries.append(SettingInfoEntry("Repeated", "Plays the Get Ready countdown again on every repeat pass, not just the first."))
            }
            if section.canTrackRecord {
                entries.append(SettingInfoEntry("Track record", "Saves your best round count here as a personal record."))
            }
        }
        return entries
    }

    /// The section's name, in the same green the exercise panel gives its subject, so a
    /// panel always says what it is editing. No edit button beside it: unlike an
    /// exercise, the section's own page is where this panel already is.
    private var titleRow: some View {
        HStack(spacing: 8) {
            // "Section:" ahead of the name, so this sheet reads as itself at a glance
            // rather than as the exercise panel's — that one names only the exercise,
            // with nothing ahead of it to tell the two apart from a title alone.
            Text("Section: \(section.displayName)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }

    /// Same shape as the exercise panel's actions, so clone and delete live in the
    /// same place whichever level you're editing.
    ///
    /// The divider belongs to the actions rather than to the settings above it — a
    /// standalone template passes nil for both handlers, and a divider over an empty row
    /// is a line with nothing under it.
    @ViewBuilder
    private var actionsRow: some View {
        if onClone != nil || onDelete != nil {
            Divider()
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
        SettingCell(title: "Autostart", value: section.autostart ? "on" : "off") {
            autostartBinding.wrappedValue.toggle()
        }
    }

    private var repeatRow: some View {
        // Displays `effectiveRepeatCount` while binding the raw `repeatCount` — a stored
        // 0 from an older row still reads as "no" rather than as a stalled section.
        // Always compact: every one of this row's slots — `.settingColumn` for `.rep`,
        // paired with Rest everywhere else — is a half-width column.
        SettingStepper(
            title: "Repeat",
            value: section.effectiveRepeatCount > 1 ? "x\(section.effectiveRepeatCount)" : "no",
            columnWidth: SettingMetrics.compactLabelColumn,
            range: 1...20,
            step: 1,
            number: repeatBinding
        )
    }

    /// Get Ready with the "Repeated" flag beside it — the two halves of one question,
    /// how the count-in behaves. Get Ready takes its half whether or not Repeated is
    /// there, so changing the repeat count never moves it.
    @ViewBuilder
    private var getReadyPairRow: some View {
        // Guarded on the step, not left to `getReadyRow`'s own check: the fixed halves
        // would otherwise hold open an empty row for a section that has no Get Ready to
        // show. Every `.time` section is created with one, so this is insurance.
        if getReadyStep(of: section) != nil {
            SettingPairRow(contentWidth: contentSize.width) {
                getReadyRow
            } trailing: {
                repeatGetReadyRow
            }
        }
    }

    /// The EMOM/AMRAP twin of `getReadyPairRow`, over the section's own duration rather
    /// than a step — so all three types ask the count-in question the same way.
    private var quickGetReadyPairRow: some View {
        SettingPairRow(contentWidth: contentSize.width) {
            quickGetReadyRow
        } trailing: {
            repeatGetReadyRow
        }
    }

    /// EMOM only: To failure with Track record beside it, the same "control paired with
    /// what it unlocks" idiom `repeatGetReadyRow` uses. `trackRecordRow` already hides
    /// itself when `canTrackRecord` is false, so the right half just sits empty until
    /// To failure is switched on — the pairing is what puts the record it then offers
    /// directly beside the toggle that made it possible, rather than a scroll away.
    private var toFailureTrackRecordPairRow: some View {
        SettingPairRow(contentWidth: contentSize.width) {
            emomToFailureRow
        } trailing: {
            trackRecordRow
        }
    }

    /// How many passes, and the breather between them. Paired for the same reason Get
    /// Ready and Repeated are: Section rest only means anything once there is more than
    /// one pass, so it belongs beside the control that decides that.
    private var repeatPairRow: some View {
        SettingPairRow(contentWidth: contentSize.width) {
            repeatRow
        } trailing: {
            sectionRestRow
        }
    }

    /// Edits the section's real get-ready step in place. It stays a `TimeSectionStep`
    /// the runner plays — only its presentation moved here from the exercise list.
    @ViewBuilder
    private var getReadyRow: some View {
        if let step = getReadyStep(of: section) {
            SettingStepper(
                title: "Get Ready",
                value: step.durationSeconds > 0 ? "\(step.durationSeconds)" : "off",
                unit: step.durationSeconds > 0 ? "s" : nil,
                columnWidth: SettingMetrics.compactLabelColumn,
                range: 0...300,
                step: 5,
                number: Binding(
                    get: { step.durationSeconds },
                    set: { newValue in
                        step.durationSeconds = newValue
                        step.markDirty()
                        try? context.save()
                    }
                )
            )
        }
    }

    /// EMOM and AMRAP hold their get-ready as a plain duration on the section rather than
    /// as a step: neither type has a step list to put one in, and `0` — every section
    /// written before this existed — means no get-ready at all.
    private var quickGetReadyRow: some View {
        SettingStepper(
            title: "Get Ready",
            value: section.getReadySeconds > 0 ? "\(section.getReadySeconds)" : "off",
            unit: section.getReadySeconds > 0 ? "s" : nil,
            columnWidth: SettingMetrics.compactLabelColumn,
            range: 0...300,
            step: 5,
            number: Binding(
                get: { section.getReadySeconds },
                set: { newValue in
                    section.getReadySeconds = newValue
                    section.markDirty()
                    try? context.save()
                }
            )
        )
    }

    /// Only when there is both something to repeat and more than one pass to repeat it
    /// over — on a section that runs once, or one with no count-in, it would be a control
    /// with nothing to control.
    @ViewBuilder
    private var repeatGetReadyRow: some View {
        if section.effectiveRepeatCount > 1, hasCountIn {
            SettingCell(
                title: "Repeated",
                value: section.repeatsGetReadyEachPass ? "on" : "off"
            ) {
                update {
                    try WorkoutEditingService.updateRepeatsGetReady(
                        section, to: !section.repeatsGetReadyEachPass, context: context
                    )
                }
            }
        }
    }

    /// Independent of the count-in: a breather between passes is worth having either way.
    /// Labelled plain "Rest" — this panel is already about the one section, so "Section"
    /// in front of it said nothing "Repeat" and "Get Ready" beside it didn't already say.
    @ViewBuilder
    private var sectionRestRow: some View {
        if section.effectiveRepeatCount > 1 {
            SettingStepper(
                title: "Rest",
                value: section.sectionRestSeconds > 0 ? "\(section.sectionRestSeconds)" : "off",
                unit: section.sectionRestSeconds > 0 ? "s" : nil,
                columnWidth: SettingMetrics.compactLabelColumn,
                range: 0...300,
                step: 5,
                number: sectionRestBinding
            )
        }
    }

    /// Whether this section plays a count-in at all, whichever way it stores one.
    private var hasCountIn: Bool {
        switch section.sectionType {
        case .time: return (getReadyStep(of: section)?.durationSeconds ?? 0) > 0
        case .emom, .amrap: return section.getReadySeconds > 0
        case .rep: return false
        }
    }

    private var emomRoundsRow: some View {
        SettingStepper(
            title: "Rounds",
            value: "\(section.emomRoundCount)",
            unit: " (min)",
            columnWidth: SettingMetrics.compactLabelColumn,
            range: 1...60,
            step: 1,
            number: emomRoundsBinding
        )
    }

    private var emomToFailureRow: some View {
        SettingCell(title: "To failure", value: section.emomToFailure ? "on" : "off") {
            update {
                try WorkoutEditingService.updateEmomToFailure(
                    section, to: !section.emomToFailure, context: context
                )
            }
        }
    }

    /// Offered on AMRAP always, and on EMOM only once the rounds are open-ended: a fixed
    /// ten-round EMOM you finish records ten every single time, which is a record that
    /// can never move.
    ///
    /// Absent rather than inert when it doesn't apply. It used to stay visible with a
    /// "Needs To failure" footnote, on the reasoning that a control which vanishes reads
    /// as one that doesn't exist — but the switch that brings it back sits directly above
    /// it, so the pair reads as cause and effect rather than as a missing feature.
    @ViewBuilder
    private var trackRecordRow: some View {
        if section.canTrackRecord {
            VStack(alignment: .leading, spacing: 2) {
                SettingCell(title: "Track record", value: section.tracksRecord ? "on" : "off") {
                    update {
                        try WorkoutEditingService.updateTracksRecord(
                            section, to: !section.tracksRecord, context: context
                        )
                    }
                }

                if isRecordLocked {
                    Text("Holds a record. Delete it in Records to edit this section again.")
                        .font(.caption2)
                        .foregroundStyle(Color.appInkMuted)
                } else if section.tracksRecord {
                    Text("Locks once you've done it, and becomes a template.")
                        .font(.caption2)
                        .foregroundStyle(Color.appInkMuted)
                }
            }
        }
    }

    /// Locked by its own record rather than by a parent workout — the state where every
    /// setting but `trackRecordRow` is inert.
    private var isRecordLocked: Bool {
        section.tracksRecord && section.recordLockedAt != nil
    }

    private var amrapDurationRow: some View {
        SettingStepper(
            title: "Duration",
            value: "\(section.amrapDurationSeconds / 60)",
            unit: " min",
            columnWidth: SettingMetrics.compactLabelColumn,
            range: 1...60,
            step: 1,
            number: amrapMinutesBinding
        )
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

    private var sectionRestBinding: Binding<Int> {
        Binding(get: { section.sectionRestSeconds }, set: { newValue in update { try WorkoutEditingService.updateSectionRest(section, to: newValue, context: context) } })
    }

    private func update(_ work: () throws -> Void) {
        do { try work() }
        catch { onError(error.localizedDescription) }
    }
}
