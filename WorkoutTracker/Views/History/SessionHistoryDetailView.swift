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
                                Text(log.exerciseNameSnapshot ?? log.exercise?.name ?? "Exercise")
                                Text("Set \(log.setIndex + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if log.isCancelled {
                                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("\(log.reps) × \(formattedWeight(log.weight, unit: log.weightUnit))")
                                    .font(.subheadline)
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
                            Text(log.timeBlockStep?.stepType == .getReady ? "Get Ready" : (log.stepExerciseNameSnapshot ?? "Rest"))
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

    private func formattedWeight(_ value: Double, unit: String) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
    }
}
