import SwiftUI
import SwiftData

struct SessionHistoryDetailView: View {
    let session: WorkoutSession

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

            if !sortedSetLogs.isEmpty {
                Section("Sets Logged") {
                    ForEach(sortedSetLogs) { log in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(log.exerciseNameSnapshot ?? log.exercise?.displayName ?? "Exercise")
                                Text(setLabel(for: log))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if log.isCancelled {
                                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                            } else if let holdSeconds = log.holdSeconds {
                                Text("Held \(holdSeconds)s")
                                    .font(.subheadline)
                            } else {
                                HStack(spacing: 4) {
                                    if let color = levelColor(for: log) {
                                        Circle().fill(color.color).frame(width: 6, height: 6)
                                    }
                                    Text(log.isBodyweight == true
                                         ? "\(log.reps) × Bodyweight"
                                         : "\(log.reps) × \(formattedWeight(log.weight, unit: log.weightUnit, exercise: log.exercise))")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }

            if !sortedStepLogs.isEmpty {
                Section("Steps Completed") {
                    ForEach(sortedStepLogs) { log in
                        HStack(spacing: 12) {
                            IconBadge(
                                systemName: log.outcome == .completed ? "checkmark" : "arrow.uturn.forward",
                                tint: log.outcome == .completed ? .green : .secondary,
                                size: 28
                            )
                            Text(log.timeSectionStep?.stepType == .getReady ? "Get Ready" : (log.stepExerciseNameSnapshot ?? "Rest"))
                            Spacer()
                            Text("\(log.actualDurationSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if sortedSetLogs.isEmpty && sortedStepLogs.isEmpty {
                Text("Nothing was logged in this session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .themedListBackground()
        .navigationTitle(session.workout?.name ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedSetLogs: [SetLog] {
        session.setLogs.sorted { $0.loggedAt < $1.loggedAt }
    }

    /// Side-tracked exercises log two sets per index, so the side has to appear or the
    /// list reads "Set 1" twice with no way to tell them apart.
    private func setLabel(for log: SetLog) -> String {
        let base = "Set \(log.setIndex + 1)"
        guard let side = log.side else { return base }
        return "\(base) · \(side.label)"
    }

    private var sortedStepLogs: [StepLog] {
        session.stepLogs.sorted { $0.sortOrder < $1.sortOrder }
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
