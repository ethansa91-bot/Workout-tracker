import SwiftUI
import SwiftData

struct SessionHistoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var pendingDelete: WorkoutSession?

    private var sessions: [WorkoutSession] {
        allSessions.filter { $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageTitleBand(title: "History", reservesButtonRow: true)

                Group {
                    if sessions.isEmpty {
                        ContentUnavailableView(
                            "No History Yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Workouts you start will show up here.")
                        )
                    } else {
                        List {
                            ForEach(sessions) { session in
                                NavigationLink {
                                    SessionHistoryDetailView(session: session)
                                } label: {
                                    sessionRow(session)
                                }
                                .fullBleedRow(isLast: session.id == sessions.last?.id)
                                // A finished workout is the record you came here for —
                                // only the unfinished ones are clutter worth clearing.
                                .swipeActions(edge: .trailing) {
                                    if session.status != .finished {
                                        Button(role: .destructive) {
                                            pendingDelete = session
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .contextMenu {
                                    if session.status != .finished {
                                        Button(role: .destructive) {
                                            pendingDelete = session
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .fullBleedList()
                        .alert("Delete this session?", isPresented: deleteAlertBinding) {
                            Button("Delete", role: .destructive) { deleteSession() }
                            Button("Cancel", role: .cancel) { pendingDelete = nil }
                        } message: {
                            Text("Everything logged in it will be permanently deleted.")
                        }
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }


    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func deleteSession() {
        guard let session = pendingDelete, session.status != .finished else {
            pendingDelete = nil
            return
        }
        WorkoutSessionService.delete(session, context: context)
        pendingDelete = nil
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
