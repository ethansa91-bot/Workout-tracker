import SwiftUI
import SwiftData

/// Enter someone's share code to start following them.
struct FollowUserSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var name = AppSettings.displayName ?? ""
    @State private var isLooking = false
    @State private var errorMessage: String?
    /// Set when the follow landed but the public announcement didn't. Deliberately not
    /// an error: the follow happened, only reciprocation is pending.
    @State private var noticeMessage: String?

    /// Following is mutual, so the other side gets a row for this user the moment this
    /// completes. Asking for a name first — once, only if there isn't one — is what stops
    /// that row reading `ACDE-3F7K`.
    private var needsName: Bool { !AppSettings.hasDisplayName }

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

                if needsName {
                    Section {
                        TextField("Your name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Your Name")
                    } footer: {
                        Text("Following goes both ways, so they'll be following you too. Your name is what they'll see — without one they just see your code.")
                    }
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
                .disabled(isLooking || !ShareCode.isPlausible(code) || (needsName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .padding()
                .background(.thickMaterial)
            }
            .alert("Following", isPresented: Binding(
                get: { noticeMessage != nil },
                set: { if !$0 { noticeMessage = nil } }
            )) {
                Button("OK") { noticeMessage = nil; dismiss() }
            } message: {
                Text(noticeMessage ?? "")
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

            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != AppSettings.displayName {
                // Best-effort: a name that fails to save is worth less than the follow
                // the user actually asked for, and Sharing settings can set it later.
                try? await SharingService.setDisplayName(trimmed)
            }

            // Revive-or-insert, plus the public follow record that makes it mutual —
            // both live in FollowService so the link sheet and the sweep can't drift.
            let outcome = try await FollowService.follow(profile, context: context)
            // The follow itself succeeded either way. Only reciprocation is in doubt, and
            // reporting that as "couldn't follow" would be plainly false.
            if outcome.isFullyMutual {
                dismiss()
            } else {
                noticeMessage = FollowService.pendingReciprocationNotice
            }
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }
}
