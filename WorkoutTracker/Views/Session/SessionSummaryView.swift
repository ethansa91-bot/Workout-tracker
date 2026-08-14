import SwiftUI
import SwiftData

/// Shown right after a session finishes: the result is always saved locally first,
/// with the option to sync now (or sync everything), or leave it for later — per spec,
/// finishing never blocks on the network.
struct SessionSummaryView: View {
    let session: WorkoutSession
    let workout: Workout
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?

    private var isOnline: Bool { NetworkReachability.shared.isOnline }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Workout Complete!")
                    .font(.appSerif(.title))
                Text(workout.name)
                    .font(.headline)
                    .foregroundStyle(Color.appInkMuted)

                VStack(spacing: 0) {
                    LabeledContent("Duration", value: durationString)
                        .padding(12)
                    Divider()
                    LabeledContent("Sets logged", value: "\(loggedSetCount)")
                        .padding(12)
                }
                .cardStyle(cornerRadius: 14)

                Spacer()

                syncSection

                Button {
                    onDone()
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationBarBackButtonHidden(true)
            .alert("Sync failed", isPresented: Binding(
                get: { syncErrorMessage != nil },
                set: { if !$0 { syncErrorMessage = nil } }
            )) {
                Button("OK") { syncErrorMessage = nil }
            } message: {
                Text(syncErrorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        if !isOnline {
            Text("Saved on this device — offline. It'll sync next time you're online.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if isSyncing {
            ProgressView("Syncing…")
        } else {
            VStack(spacing: 10) {
                Text("Saved on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    syncNow()
                } label: {
                    Text("Sync Everything").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
    }

    private var loggedSetCount: Int {
        session.setLogs.filter { !$0.isCancelled }.count
    }

    private var durationString: String {
        let total = Int(session.elapsedSeconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func syncNow() {
        isSyncing = true
        Task {
            do {
                try await SyncEngine.shared.syncAll(context: context)
            } catch {
                syncErrorMessage = error.localizedDescription
            }
            isSyncing = false
        }
    }
}
