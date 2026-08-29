import SwiftUI
import SwiftData

/// One past session, laid out the way the workout itself is: a band per section, one
/// row per exercise, and that exercise's sets nested inside it.
///
/// The skeleton comes from `session.workout?.sortedSections`, not from the logs. Logs
/// alone can't produce an EMOM or AMRAP section — those runners write none at all — and
/// can't show a section an abandoned session never reached. Logs are attached into the
/// skeleton instead, which also means a repeated section can be shown once per round.
struct SessionHistoryDetailView: View {
    let session: WorkoutSession

    /// One section, one pass through it. A section with `repeatCount` 3 makes three of
    /// these, each carrying only its own round's logs.
    private struct PassGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let rows: [ExerciseRow]
    }

    /// One exercise (or one Follow Along step) within a pass.
    private struct ExerciseRow: Identifiable {
        let id: String
        let position: Int
        let title: String
        /// The right-hand summary — "3 of 3 sets", "30s · Skipped", "Not logged".
        let detail: String?
        /// Muted where the detail is an absence rather than a result.
        var detailIsAbsence: Bool = false
        /// A Follow Along step's own color, so a colored step keeps its identity here.
        var tint: Color?
        /// Empty for everything but rep exercises — only they log per-set results.
        var lines: [SetLine] = []
    }

    /// One logged set, already resolved to display strings.
    private struct SetLine: Identifiable {
        let id: UUID
        let label: String
        let value: String
        /// Level-based equipment's own color, matching how records show a level.
        var dot: Color?
    }

    var body: some View {
        List {
            Section {
                DetailHeader(
                    systemName: "clock.arrow.circlepath",
                    title: session.workout?.name ?? "Session",
                    subtitle: session.startedAt.formatted(date: .abbreviated, time: .shortened),
                    tint: statusColor
                )
                LabeledContent("Duration", value: durationString)
                LabeledContent("Status") {
                    StatusPill(text: statusText, tint: statusColor)
                }
            }

            if let groups = passGroups {
                ForEach(groups) { group in
                    Section {
                        if group.rows.isEmpty {
                            emptyRow("This section has no exercises.")
                        } else {
                            ForEach(group.rows) { row in
                                exerciseRow(row, isLast: row.id == group.rows.last?.id)
                            }
                        }
                    } header: {
                        ListBandHeader(title: group.title, subtitle: group.subtitle)
                    }
                }
            } else {
                // The workout was deleted out from under this session — `Workout`'s
                // sessions relationship is `.nullify`, so this is a real state, and
                // there's no structure left to lay the logs out against. The flat lists
                // are all that can be shown.
                flatFallback
            }
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) { PushedTitleBand(title: session.workout?.name ?? "Session") }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func exerciseRow(_ row: ExerciseRow, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                NumberBadge(number: row.position, tint: row.tint ?? .accentColor)
                Text(row.title)
                Spacer(minLength: 8)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(row.detailIsAbsence ? Color.appInkMuted : Color.appRust)
                }
            }

            // Indented past the badge, so the sets read as belonging to the name above
            // them rather than as rows of their own.
            if !row.lines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(row.lines) { line in
                        HStack(spacing: 6) {
                            Text(line.label)
                                .foregroundStyle(Color.appInkMuted)
                            Spacer(minLength: 8)
                            if let dot = line.dot {
                                Circle().fill(dot).frame(width: 6, height: 6)
                            }
                            Text(line.value)
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fullBleedRow(isLast: isLast)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.appInkMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .fullBleedRow()
    }

    // MARK: - Structure

    /// nil when the workout is gone, which is what selects the flat fallback.
    private var passGroups: [PassGroup]? {
        guard let workout = session.workout else { return nil }
        return workout.sortedSections.flatMap { section in
            (0..<section.effectiveRepeatCount).map { pass in
                PassGroup(
                    id: "\(section.id)-\(pass)",
                    title: sectionRoundTitle(section, repeatIndex: pass),
                    subtitle: sectionKindSummary(section),
                    rows: rows(for: section, pass: pass)
                )
            }
        }
    }

    private func rows(for section: WorkoutSection, pass: Int) -> [ExerciseRow] {
        switch section.sectionType {
        case .rep:
            return section.sortedRepExercises.enumerated().map { index, entry in
                let lines = setLines(for: entry, pass: pass)
                return ExerciseRow(
                    id: "\(entry.id)-\(pass)",
                    position: index + 1,
                    title: entry.exercise?.displayName ?? "Exercise",
                    detail: lines.isEmpty ? "Not logged" : "\(lines.count) of \(entry.totalSetSlots) sets",
                    detailIsAbsence: lines.isEmpty,
                    lines: lines
                )
            }
        case .time:
            // Get Ready and Rest are kept, for the same reason `SessionExerciseListView`
            // keeps them: the runner played them, so leaving them out would make this
            // disagree with what actually happened.
            return section.sortedTimeSteps.enumerated().map { index, step in
                let log = session.stepLogs.first {
                    $0.timeSectionStep?.id == step.id && $0.repeatIndex == pass
                }
                return ExerciseRow(
                    id: "\(step.id)-\(pass)",
                    position: index + 1,
                    title: stepTitle(step),
                    detail: stepDetail(log),
                    detailIsAbsence: log == nil,
                    tint: step.resolvedColor.color
                )
            }
        case .emom, .amrap:
            // These runners write no logs at all, so the exercises are listed for
            // completeness and the section's own summary carries the rounds/duration.
            return section.sortedQuickExercises.enumerated().map { index, entry in
                ExerciseRow(
                    id: "\(entry.id)-\(pass)",
                    position: index + 1,
                    title: entry.exercise?.displayName ?? "Exercise",
                    detail: nil
                )
            }
        }
    }

    /// Scoped to one pass — the same rule the runner logs by, so a section run three
    /// times doesn't show all three rounds' sets under the first.
    private func setLines(for entry: RepSectionExercise, pass: Int) -> [SetLine] {
        let logs = session.setLogs.filter {
            $0.repSectionExercise?.id == entry.id && !$0.isCancelled && $0.repeatIndex == pass
        }
        // Left before Right within a set index, so a side-tracked exercise reads in the
        // order it was performed. Written out rather than as a tuple compare: `Bool`
        // isn't `Comparable`, and the sides only need separating when the indices tie.
        let sorted = logs.sorted { first, second in
            if first.setIndex != second.setIndex { return first.setIndex < second.setIndex }
            return first.side == .left && second.side == .right
        }
        return sorted.map { log in
            SetLine(
                id: log.id,
                label: setLabel(for: log),
                value: setValue(for: log),
                dot: levelColor(for: log)?.color
            )
        }
    }

    private func stepTitle(_ step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    private func stepDetail(_ log: StepLog?) -> String {
        guard let log else { return "Not reached" }
        let duration = "\(log.actualDurationSeconds)s"
        return log.outcome == .completed ? duration : "\(duration) · Skipped"
    }

    // MARK: - Fallback for a deleted workout

    @ViewBuilder
    private var flatFallback: some View {
        let sets = sortedSetLogs
        let steps = sortedStepLogs

        if !sets.isEmpty {
            Section {
                ForEach(sets) { log in
                    exerciseRow(
                        ExerciseRow(
                            id: log.id.uuidString,
                            position: log.setIndex + 1,
                            title: log.exerciseNameSnapshot ?? log.exercise?.displayName ?? "Exercise",
                            detail: setValue(for: log)
                        ),
                        isLast: log.id == sets.last?.id
                    )
                }
            } header: {
                ListBandHeader(title: "Sets Logged")
            }
        }

        if !steps.isEmpty {
            Section {
                ForEach(steps) { log in
                    exerciseRow(
                        ExerciseRow(
                            id: log.id.uuidString,
                            position: log.sortOrder + 1,
                            title: log.timeSectionStep?.stepType == .getReady
                                ? "Get Ready"
                                : (log.stepExerciseNameSnapshot ?? "Rest"),
                            detail: stepDetail(log)
                        ),
                        isLast: log.id == steps.last?.id
                    )
                }
            } header: {
                ListBandHeader(title: "Steps Completed")
            }
        }

        if sets.isEmpty && steps.isEmpty {
            emptyRow("Nothing was logged in this session.")
        }
    }

    /// Cancelled sets are excluded, matching how the rest of the app already treats
    /// them — `SessionSummaryView`'s count, `RecordsListView`'s query and every
    /// `SetLogQueries` predicate all skip them.
    private var sortedSetLogs: [SetLog] {
        session.setLogs
            .filter { !$0.isCancelled }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var sortedStepLogs: [StepLog] {
        session.stepLogs.sorted { $0.loggedAt < $1.loggedAt }
    }

    // MARK: - Formatting

    /// Side-tracked exercises log two sets per index, so the side has to appear or the
    /// list reads "Set 1" twice with no way to tell them apart.
    private func setLabel(for log: SetLog) -> String {
        let base = "Set \(log.setIndex + 1)"
        guard let side = log.side else { return base }
        return "\(base) · \(side.label)"
    }

    private func setValue(for log: SetLog) -> String {
        if let holdSeconds = log.holdSeconds { return "\(holdSeconds)s" }
        if log.isBodyweight == true { return "\(log.reps) × Bodyweight" }
        return "\(log.reps) × \(formattedWeight(log.weight, unit: log.weightUnit, exercise: log.exercise))"
    }

    private var statusText: String {
        switch session.status {
        case .finished: return "Finished"
        case .abandonedUnfinished: return "Unfinished"
        case .paused: return "Paused"
        case .inProgress: return "In Progress"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .finished: return .green
        case .abandonedUnfinished: return .orange
        case .paused, .inProgress: return .accentColor
        }
    }

    private var durationString: String {
        let total = Int(session.elapsedSeconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func formattedWeight(_ value: Double, unit: String, exercise: Exercise?) -> String {
        if unit == Equipment.levelUnit, let equipment = exercise?.weightedEquipment, equipment.isLevelBased {
            if let combo = equipment.sortedWeightCombos.first(where: { $0.value == value }) {
                return combo.levelDisplayName
            }
            return "Level \(Int(value))"
        }
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
    }

    private func levelColor(for log: SetLog) -> PaletteColor? {
        guard log.weightUnit == Equipment.levelUnit,
              let equipment = log.exercise?.weightedEquipment,
              equipment.isLevelBased else { return nil }
        return equipment.sortedWeightCombos.first(where: { $0.value == log.weight })?.color
    }
}
