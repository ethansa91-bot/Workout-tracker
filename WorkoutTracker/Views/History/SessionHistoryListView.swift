import SwiftUI
import SwiftData

/// Mounts the history list only while its tab is the one on screen — see
/// `RecordsListView` for why. `@Query` over every session re-runs on each save, and a
/// workout saves constantly, so an off-screen copy of this view charged every logged set
/// for a fetch of the whole of session history.
///
/// The tradeoff is that leaving and returning rebuilds the list, so the scroll position
/// resets.
struct SessionHistoryListView: View {
    /// Whether this is the selected tab.
    let isSelected: Bool

    var body: some View {
        if isSelected {
            SessionHistoryListContent()
        } else {
            Color.appBackground.ignoresSafeArea()
        }
    }
}

private struct SessionHistoryListContent: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var pendingDelete: WorkoutSession?

    private var sessions: [WorkoutSession] {
        allSessions.filter { $0.deletedAt == nil }
    }

    var body: some View {
        // Read once, not once per row — `sessions.last?.id` inside the `ForEach` re-ran
        // the filter over the whole of session history for every row on screen.
        let sessions = self.sessions
        let lastID = sessions.last?.id

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
                                .fullBleedRow(isLast: session.id == lastID)
                                // Finished sessions included: they used to be protected
                                // as "the record you came here for", but a mis-logged
                                // one is exactly what you'd want to clear, and the alert
                                // already spells out what goes with it.
                                .swipeActions(edge: .trailing) {
                                    // Not `role: .destructive`: a destructive swipe
                                    // button plays the row-removal animation on tap,
                                    // before any data changes — so the row vanished, the
                                    // confirmation appeared, and the row came back. The
                                    // role belongs on the alert's confirm button.
                                    Button {
                                        pendingDelete = session
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(Color.appDanger)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDelete = session
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .fullBleedList()
                        .alert("Delete this session?", isPresented: deleteAlertBinding) {
                            Button("Delete", role: .destructive) { deleteSession() }
                            Button("Cancel", role: .cancel) { pendingDelete = nil }
                        } message: {
                            // The unlock is worth saying: `Workout.isLocked` is "has any
                            // live session", so clearing the last one quietly makes the
                            // workout editable again.
                            Text("Everything logged in it will be permanently deleted. If it was the workout's last session, the workout becomes editable again.")
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
        guard let session = pendingDelete else { return }
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
