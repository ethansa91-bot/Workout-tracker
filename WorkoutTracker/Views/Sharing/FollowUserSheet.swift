import SwiftUI
import SwiftData

/// Enter someone's share code to start following them.
struct FollowUserSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [FollowedUser]

    @State private var code = ""
    @State private var isLooking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD-3F7K", text: $code)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) { _, newValue in
                            // Reformat as they type so the grouping matches what they're
                            // copying from, without fighting the cursor.
                            let normalized = ShareCode.normalize(newValue)
                            let formatted = ShareCode.format(normalized)
                            if formatted != newValue && normalized.count <= ShareCode.length {
                                code = formatted
                            }
                        }
                } header: {
                    Text("Share Code")
                } footer: {
                    Text("Ask the person for their code — they'll find it in Settings under Sharing. Codes are 8 characters and aren't case sensitive.")
                }
            }
            .themedListBackground()
            .navigationTitle("Follow Someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await follow() }
                } label: {
                    Group {
                        if isLooking {
                            ProgressView()
                        } else {
                            Text("Follow").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.appAccent.opacity(0.25))
                .foregroundStyle(Color.appAccent)
                .disabled(isLooking || !ShareCode.isPlausible(code))
                .padding()
                .background(.thickMaterial)
            }
            .alert("Couldn't Follow", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func follow() async {
        isLooking = true
        defer { isLooking = false }

        do {
            let profile = try await SharingService.lookup(code: code)

            // Re-following someone already followed should revive the existing row
            // rather than creating a second one — including one previously unfollowed,
            // which is a tombstone rather than an absence.
            if let match = existing.first(where: { $0.ownerRecordName == profile.recordName }) {
                match.deletedAt = nil
                match.shareCode = profile.shareCode
                match.displayName = profile.displayName
                match.markDirty()
            } else {
                let user = FollowedUser(
                    ownerRecordName: profile.recordName,
                    shareCode: profile.shareCode,
                    displayName: profile.displayName
                )
                context.insert(user)
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }
}
