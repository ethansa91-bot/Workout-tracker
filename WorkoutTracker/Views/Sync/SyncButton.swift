import SwiftUI

/// Supabase sync is disconnected for now (see `SyncEngine.isDisabled`) — shown as a
/// permanently disabled button rather than removed, so it's ready to come back once
/// CloudKit sync replaces it. Previously reflected online/dirty/syncing state; that
/// logic is dormant, not deleted, since `isDirty`/`sync` are still threaded through
/// from every call site.
struct SyncButton: View {
    let isDirty: Bool
    let sync: () async -> Void

    var body: some View {
        Button("Sync") {}
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
            .disabled(true)
    }
}
