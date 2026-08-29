import SwiftUI
import SwiftData
import UIKit

/// The sharing hub: this user's own code, and the people they follow.
struct SharingHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FollowedUser.followedAt, order: .reverse) private var allFollowed: [FollowedUser]

    @State private var profile: SharedProfile?
    @State private var displayName = AppSettings.displayName ?? ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingFollowSheet = false
    @State private var showingPublishSheet = false
    @State private var showingRotateConfirm = false
    @State private var pendingUnfollow: FollowedUser?
    @State private var setupSteps: [SharingSetupCheck.Step] = []
    @State private var isCheckingSetup = false

    private var router = SharingRouter.shared

    private var reachability: NetworkReachability { NetworkReachability.shared }

    private var followed: [FollowedUser] {
        allFollowed.filter { $0.deletedAt == nil }
    }

    var body: some View {
        Form {
            Section {
                if let profile {
                    TextField("Your name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await saveDisplayName() } }
                    LabeledContent("Your code") {
                        Text(ShareCode.format(profile.shareCode))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    ShareLink(
                        item: ShareLinkURL.follow(code: profile.shareCode),
                        subject: Text("Follow my workouts"),
                        message: Text(shareMessage(for: profile)),
                        preview: SharePreview("Follow my workouts in Workout Tracker")
                    ) {
                        Label("Share My Link", systemImage: "square.and.arrow.up")
                    }
                    Button("Get a New Code", role: .destructive) { showingRotateConfirm = true }
                        .foregroundStyle(Color.appDanger)
                } else if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else {
                    Button("Set Up Sharing") { Task { await loadProfile() } }
                }
            } header: {
                Text("Your Code")
            } footer: {
                // Deliberately does not claim rotating revokes access: people already
                // following you are matched on your account, not your code, so they keep
                // seeing your workouts. A new code only stops *new* people using the old
                // one. Saying otherwise would be telling the user they're protected when
                // they aren't.
                Text("Share your link and whoever opens it follows you — and you follow them back automatically. Your name is what they'll see. Anyone with your code can see the workouts you publish, so only share it with people you want to. A new code stops the old one being used to follow you; people already following you stay, and you can remove them individually below.")
            }

            Section {
                Button("Publish Workouts") { showingPublishSheet = true }
                    .disabled(profile == nil)
            } header: {
                Text("Your Workouts")
            } footer: {
                Text("Choose which of your workouts other people can see. Nothing is shared until you publish it.")
            }

            Section {
                if followed.isEmpty {
                    Text("You're not following anyone yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(followed) { user in
                        NavigationLink {
                            FollowedUserDetailView(user: user)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.resolvedDisplayName)
                                HStack(spacing: 6) {
                                    Text(ShareCode.format(user.shareCode))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    if user.followsMe {
                                        StatusPill(
                                            text: "Follows you",
                                            icon: "arrow.left.arrow.right",
                                            tint: Color.appAccent
                                        )
                                    }
                                }
                            }
                        }
                        .swipeActions {
                            // Not `role: .destructive` — that plays the row-removal
                            // animation before the confirmation is even answered.
                            Button("Unfollow") { pendingUnfollow = user }
                                .tint(Color.appDanger)
                        }
                    }
                }
                Button("Follow Someone") { showingFollowSheet = true }
            } header: {
                Text("Following")
            } footer: {
                Text("Open someone's link, or enter their code, to see the workouts they publish. Following goes both ways — they'll be following you too, and they're told when it happens.")
            }

            setupSection

            if !reachability.isOnline {
                Section {
                    Label("You're offline", systemImage: "wifi.slash")
                        .foregroundStyle(Color.appDanger)
                } footer: {
                    Text("Sharing needs an internet connection.")
                }
            }
        }
        .themedListBackground()
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
        .sheet(isPresented: $showingFollowSheet) {
            FollowUserSheet()
        }
        .sheet(isPresented: $showingPublishSheet) {
            PublishWorkoutSheet()
        }
        .alert("Get a new code?", isPresented: $showingRotateConfirm) {
            Button("Get New Code", role: .destructive) { Task { await rotate() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The old code and link stop working, so nobody new can use them to follow you. People already following you are unaffected — unfollow them individually to remove them.")
        }
        .alert("Unfollow?", isPresented: Binding(
            get: { pendingUnfollow != nil },
            set: { if !$0 { pendingUnfollow = nil } }
        )) {
            Button("Unfollow", role: .destructive) { unfollow() }
            Button("Cancel", role: .cancel) { pendingUnfollow = nil }
        } message: {
            Text("You'll stop seeing \(pendingUnfollow?.resolvedDisplayName ?? "their") workouts, and you'll be removed from their followers. They may still be following you — that's their choice to undo. Workouts you've already saved stay in your library.")
        }
        .alert("Sharing", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Reports why sharing isn't working, when it isn't.
    ///
    /// The automatic follow-back sweep runs unprompted, so its failures are parked on the
    /// router rather than shown as an alert — this is where they surface. Without it a
    /// CloudKit index that was never created is indistinguishable from simply having no
    /// followers yet, which is exactly how it went unnoticed.
    @ViewBuilder
    private var setupSection: some View {
        Section {
            if let failure = router.lastSweepFailure, setupSteps.isEmpty {
                Label(
                    "Couldn't check for new followers",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(Color.appDanger)
                Text(describe(failure))
                    .font(.caption)
                    .foregroundStyle(Color.appInkMuted)
            }

            ForEach(setupSteps) { step in
                SetupStepRow(step: step)
            }

            Button {
                Task { await runSetupCheck() }
            } label: {
                if isCheckingSetup {
                    HStack {
                        ProgressView()
                        Text("Checking…").foregroundStyle(.secondary)
                    }
                } else {
                    Label("Check Setup", systemImage: "stethoscope")
                }
            }
            .disabled(isCheckingSetup)

            if !setupSteps.isEmpty {
                Button("Copy Report") {
                    UIPasteboard.general.string = SharingSetupCheck.transcript(setupSteps)
                }
            }
        } header: {
            Text("Sharing Status")
        } footer: {
            Text("Checks that following, publishing and automatic follow-back can actually reach iCloud, and names what's wrong if they can't.")
        }
    }

    private func runSetupCheck() async {
        isCheckingSetup = true
        defer { isCheckingSetup = false }
        setupSteps = await SharingSetupCheck.run(context: context)
        // A passing check means the sweep's stored failure is stale.
        if !setupSteps.contains(where: \.isFailure) { router.lastSweepFailure = nil }
    }

    /// Carries the code as well as the link on purpose. Messages and Mail often render a
    /// `workouttracker://` URL as plain text rather than something tappable, and the link
    /// does nothing at all on a device without the app — so the typed-code path has to
    /// stay available in the same message.
    private func shareMessage(for profile: SharedProfile) -> String {
        """
        Follow my workouts in Workout Tracker: \(ShareLinkURL.follow(code: profile.shareCode).absoluteString)

        If that link doesn't open the app, enter my code instead: \(ShareCode.format(profile.shareCode))
        """
    }

    /// Publishes the name everyone following this user sees. Silent on failure — the
    /// field keeps what was typed, and the next save or launch retries.
    private func saveDisplayName() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (profile?.displayName ?? "") else { return }
        do {
            try await SharingService.setDisplayName(trimmed)
            if let current = profile {
                profile = SharedProfile(
                    recordName: current.recordName,
                    shareCode: current.shareCode,
                    displayName: trimmed
                )
            }
        } catch {
            errorMessage = describe(error)
        }
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resolved = try await SharingService.ensureProfile()
            profile = resolved
            displayName = resolved.displayName
            // Names are captured when a follow happens and never again, so someone who
            // named themselves later would show as a code forever without this.
            await FollowService.refreshDisplayNames(context: context)
        } catch {
            // A cached code keeps the screen useful offline, even though nothing
            // network-backed will work until the connection returns.
            if let cached = AppSettings.shareCode {
                profile = SharedProfile(recordName: "", shareCode: cached, displayName: "")
            }
            errorMessage = describe(error)
        }
    }

    private func rotate() async {
        do {
            profile = try await SharingService.rotateCode()
        } catch {
            errorMessage = describe(error)
        }
    }

    private func unfollow() {
        guard let user = pendingUnfollow else { return }
        pendingUnfollow = nil
        // Soft-deletes locally and withdraws this user's public follow record, so they
        // stop appearing in that person's follower list.
        FollowService.unfollow(user, context: context)
    }

    private func describe(_ error: Error) -> String {
        (error as? SharingError)?.errorDescription ?? CloudKitErrorFormatter.describe(error)
    }
}

/// One line of the setup check. Failures carry the fix directly under them, because a
/// CloudKit error code is only actionable next to the Console step that clears it.
private struct SetupStepRow: View {
    let step: SharingSetupCheck.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(step.title)
                Spacer()
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if case .failed(_, let fix) = step.outcome, let fix {
                Text(fix)
                    .font(.caption)
                    .foregroundStyle(Color.appRust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch step.outcome {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch step.outcome {
        case .ok: return Color.appAccent
        case .info: return Color.appInkMuted
        case .failed: return Color.appDanger
        }
    }

    private var detail: String {
        switch step.outcome {
        case .ok(let text), .info(let text): return text
        case .failed(let text, _): return text
        }
    }
}
