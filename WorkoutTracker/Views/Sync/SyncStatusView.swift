import SwiftUI
import SwiftData

/// Full bidirectional "sync everything" — a `Form` section for Settings.
struct SyncStatusView: View {
    @Environment(\.modelContext) private var context
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var lastSyncedAt = SyncState.lastSyncedAt

    private var isOnline: Bool { NetworkReachability.shared.isOnline }

    var body: some View {
        Section("Sync") {
            LabeledContent("Last synced") {
                Text(lastSyncedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    .foregroundStyle(.secondary)
            }
            if !isOnline {
                Text("Offline")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await syncAll() }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Text("Sync Everything")
                    }
                }
                .disabled(isSyncing)
            }
        }
        .alert("Sync failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func syncAll() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SyncEngine.shared.syncAll(context: context)
            lastSyncedAt = SyncState.lastSyncedAt
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
