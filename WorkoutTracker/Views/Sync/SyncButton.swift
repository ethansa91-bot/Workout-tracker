import SwiftUI

/// Reflects the states a syncable item can be in: nothing to push, online with pending
/// changes, or offline — shown as a plain label when offline, never a disabled button,
/// per spec.
struct SyncButton: View {
    let isDirty: Bool
    let sync: () async -> Void

    @State private var isSyncing = false

    private var isOnline: Bool { NetworkReachability.shared.isOnline }

    var body: some View {
        if !isOnline {
            Text("Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isSyncing {
            ProgressView()
                .controlSize(.small)
        } else if isDirty {
            Button("Sync") {
                Task {
                    isSyncing = true
                    await sync()
                    isSyncing = false
                }
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
        } else {
            Label("Synced", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
