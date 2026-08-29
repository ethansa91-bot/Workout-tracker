import SwiftUI
import SwiftData

/// What a `workouttracker://follow?code=…` link opens.
///
/// The code is already known, so unlike `FollowUserSheet` there's nothing to type — this
/// resolves immediately and the only thing it can stop for is a name. That stop is the
/// point of the screen: following is mutual, so the person on the other side is about to
/// get a row for this user, and a name set *now* is the difference between them seeing
/// "Ethan" and seeing `ACDE-3F7K`.
struct FollowByLinkSheet: View {
    let code: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .resolving
    @State private var name = AppSettings.displayName ?? ""
    @State private var isWorking = false
    /// The follow landed but the public announcement didn't; the success copy says so
    /// rather than claiming they're following back already.
    @State private var reciprocationPending = false

    private enum Phase {
        case resolving
        /// Resolved, but this user has never set a name — ask before completing.
        case needsName(SharedProfile)
        case followed(FollowedUser)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .themedListBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isFinished ? "Done" : "Cancel") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) { primaryAction }
                .task { await resolve() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .resolving:
            HStack {
                ProgressView()
                Text("Finding them…").foregroundStyle(.secondary)
            }

        case .needsName(let profile):
            Section {
                LabeledContent("Their code") {
                    Text(ShareCode.format(profile.shareCode))
                        .font(.body.monospaced())
                }
            } header: {
                Text(profile.displayName.isEmpty ? "Following" : profile.displayName)
            }

            Section {
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("Your Name")
            } footer: {
                Text("Following goes both ways, so they'll be following you too. Your name is what they'll see — without one they just see your code.")
            }

        case .followed(let user):
            Section {
                Label("You're following \(user.resolvedDisplayName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.appAccent)
            } footer: {
                Text(reciprocationPending
                    ? FollowService.pendingReciprocationNotice
                    : "They're now following you back. Their published workouts are in Settings under Sharing.")
            }

        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.appDanger)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if case .needsName(let profile) = phase {
            Button {
                Task { await complete(profile) }
            } label: {
                Group {
                    if isWorking {
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
            .disabled(isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
            .background(.thickMaterial)
        }
    }

    private var title: String {
        switch phase {
        case .resolving: return "Follow"
        case .needsName: return "Follow"
        case .followed: return "Following"
        case .failed: return "Couldn't Follow"
        }
    }

    private var isFinished: Bool {
        if case .followed = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    /// Resolves the code, then either stops for a name or completes straight away —
    /// a user who already has a name set shouldn't be asked again on every link.
    private func resolve() async {
        do {
            let profile = try await SharingService.lookup(code: code)
            if AppSettings.hasDisplayName {
                await complete(profile)
            } else {
                phase = .needsName(profile)
            }
        } catch {
            phase = .failed(describe(error))
        }
    }

    private func complete(_ profile: SharedProfile) async {
        isWorking = true
        defer { isWorking = false }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != AppSettings.displayName {
            // Best-effort: a name that fails to save is worth less than the follow the
            // user actually asked for, and Sharing settings can set it again later.
            try? await SharingService.setDisplayName(trimmed)
        }

        do {
            let outcome = try await FollowService.follow(profile, context: context)
            phase = .followed(outcome.user)
            reciprocationPending = !outcome.isFullyMutual
        } catch {
            phase = .failed(describe(error))
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? SharingError)?.errorDescription ?? CloudKitErrorFormatter.describe(error)
    }
}
