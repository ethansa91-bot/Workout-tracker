import SwiftUI
import SwiftData

/// Shown right after creating a custom equipment/exercise item, per spec: a button to
/// sync just this one thing, or everything, or just keep going and let it sync later.
struct PostSaveSyncPrompt<Model: SyncableModel>: View {
    let itemName: String
    let model: Model
    let syncSingle: () async -> Void
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var isSyncingAll = false

    private var isOnline: Bool { NetworkReachability.shared.isOnline }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("\(itemName) saved")
                .font(.appSerif(.title3))
            Text("Saved on this device. Sync it now, sync everything, or keep going — it'll sync later.")
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                if !isOnline {
                    Text("Offline — will sync later")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    SyncButton(isDirty: model.isDirty, sync: syncSingle)
                    Button {
                        Task {
                            isSyncingAll = true
                            try? await SyncEngine.shared.syncAll(context: context)
                            isSyncingAll = false
                        }
                    } label: {
                        if isSyncingAll {
                            ProgressView()
                        } else {
                            Text("Sync Everything")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
            }

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
