import SwiftUI
import SwiftData

/// The sharing hub: this user's own code, and the people they follow.
struct SharingHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FollowedUser.followedAt, order: .reverse) private var allFollowed: [FollowedUser]

    @State private var profile: SharedProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingFollowSheet = false
    @State private var showingPublishSheet = false
    @State private var showingRotateConfirm = false
    @State private var pendingUnfollow: FollowedUser?

    private var reachability: NetworkReachability { NetworkReachability.shared }

    private var followed: [FollowedUser] {
        allFollowed.filter { $0.deletedAt == nil }
    }

    var body: some View {
        Form {
            Section {
                if let profile {
                    LabeledContent("Your code") {
                        Text(ShareCode.format(profile.shareCode))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    ShareLink(
                        item: shareMessage(for: profile),
                        subject: Text("My WorkoutTracker code"),
                        message: Text(shareMessage(for: profile))
                    ) {
                        Label("Share My Code", systemImage: "square.and.arrow.up")
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
                Text("Give this code to someone and they can see the workouts you publish. Anyone with the code can see them, so only share it with people you want to. Getting a new code stops everyone who has the old one — there's no way to remove just one person.")
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.resolvedDisplayName)
                                Text(ShareCode.format(user.shareCode))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Unfollow", role: .destructive) { pendingUnfollow = user }
                        }
                    }
                }
                Button("Follow Someone") { showingFollowSheet = true }
            } header: {
                Text("Following")
            } footer: {
                Text("Enter someone's code to see their published workouts and save them to your library. They aren't told that you followed them.")
            }

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
            Text("Everyone you've given your current code to will stop seeing your workouts. You'll need to share the new code with anyone you still want to have access.")
        }
        .alert("Unfollow?", isPresented: Binding(
            get: { pendingUnfollow != nil },
            set: { if !$0 { pendingUnfollow = nil } }
        )) {
            Button("Unfollow", role: .destructive) { unfollow() }
            Button("Cancel", role: .cancel) { pendingUnfollow = nil }
        } message: {
            Text("You'll stop seeing \(pendingUnfollow?.resolvedDisplayName ?? "their") workouts. Workouts you've already saved stay in your library.")
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

    private func shareMessage(for profile: SharedProfile) -> String {
        "Follow my workouts in WorkoutTracker with my code: \(ShareCode.format(profile.shareCode))"
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await SharingService.ensureProfile()
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
        // Soft delete, so the removal reaches the user's other devices.
        SyncDeletion.delete(user, context: context)
        try? context.save()
    }

    private func describe(_ error: Error) -> String {
        (error as? SharingError)?.errorDescription ?? CloudKitErrorFormatter.describe(error)
    }
}
