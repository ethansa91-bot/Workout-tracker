import SwiftUI
import SwiftData

struct SessionHistoryListView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    private var sessions: [WorkoutSession] {
        allSessions.filter { $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished and unfinished workouts will show up here.")
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
            .background(Color.appBackground)
            .navigationTitle("History")
        }
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
