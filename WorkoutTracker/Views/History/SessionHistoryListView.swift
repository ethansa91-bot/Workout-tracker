import SwiftUI
import SwiftData

struct SessionHistoryListView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @AppStorage("settings.historyOnlyFinished") private var onlyFinished = true

    /// The default view is "what I actually did" — completed workouts, plus anything
    /// still live from today so an interrupted workout stays one tap from being
    /// resumed. A session left paused days ago isn't resumable in practice, just
    /// clutter, so it stays hidden until the filter comes off.
    private var sessions: [WorkoutSession] {
        let live = allSessions.filter { $0.deletedAt == nil }
        guard onlyFinished else { return live }
        return live.filter { session in
            switch session.status {
            case .finished:
                return true
            case .paused, .inProgress:
                return Calendar.current.isDateInToday(session.startedAt)
            case .abandonedUnfinished:
                return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Toggle("Show only finished workouts", isOn: $onlyFinished)
                    .font(.subheadline)
                    .tint(Color.appAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Group {
                    if sessions.isEmpty {
                        ContentUnavailableView(
                            onlyFinished ? "No Finished Workouts" : "No History Yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text(emptyStateMessage)
                        )
                    } else {
                        List(sessions) { session in
                            NavigationLink {
                                SessionHistoryDetailView(session: session)
                            } label: {
                                sessionRow(session)
                            }
                        }
                        .themedListBackground()
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("History")
        }
    }

    private var emptyStateMessage: String {
        onlyFinished
            ? "Workouts you finish will show up here. Turn off the filter to see paused and unfinished ones too."
            : "Finished and unfinished workouts will show up here."
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        let info = statusInfo(session)
        return HStack(spacing: 12) {
            IconBadge(systemName: info.1, tint: info.2)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.workout?.name ?? "Workout")
                    .font(.headline)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: info.0, tint: info.2)
        }
        .padding(.vertical, 2)
    }

    private func statusInfo(_ session: WorkoutSession) -> (String, String, Color) {
        switch session.status {
        case .finished: return ("Finished", "checkmark.circle.fill", .green)
        case .abandonedUnfinished: return ("Unfinished", "exclamationmark.circle.fill", .orange)
        case .paused: return ("Paused", "pause.circle.fill", .blue)
        case .inProgress: return ("In Progress", "play.circle.fill", .blue)
        }
    }
}
