//
//  ContentView.swift
//  WorkoutTracker
//
//  Created by Ethan Winiger on 09/08/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .schedule

    /// Sharing events arrive from outside the view tree — an opened link, or the
    /// reciprocal-follow sweep. Both are presented here rather than inside Settings →
    /// Sharing so they work whichever tab the user is on.
    @State private var router = SharingRouter.shared

    private enum Tab {
        case schedule, overview, records, history, settings
    }

    var body: some View {
        // iOS only collapses tabs into an automatic "More" tab once there are more
        // than 5 — five items (Library folded into Overview as a horizontal
        // pane selector instead of its own tab) all show directly, no "More".
        TabView(selection: $selectedTab) {
            ScheduleListView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Tab.schedule)

            WorkoutListView()
                .tabItem { Label("Overview", systemImage: "list.bullet.rectangle") }
                .tag(Tab.overview)

            RecordsListView(isSelected: selectedTab == .records)
                .tabItem { Label("Records", systemImage: "trophy.fill") }
                .tag(Tab.records)

            SessionHistoryListView(isSelected: selectedTab == .history)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Color.appAccent)
        .onAppear {
            // Schedule is the default landing tab, but if there's nothing scheduled
            // for today it has nothing useful to show — land on Overview instead.
            if !hasWorkoutScheduledToday() {
                selectedTab = .overview
            }
        }
        .sheet(item: $router.pendingFollow) { pending in
            FollowByLinkSheet(code: pending.code)
        }
        .overlay(alignment: .top) {
            if !router.newMutualFollows.isEmpty {
                MutualFollowBanner(
                    users: router.newMutualFollows,
                    onUndo: undoMutualFollow,
                    onDismiss: dismissMutualFollowNotice
                )
            }
        }
        .animation(.snappy, value: router.newMutualFollows.map(\.id))
        .task { await syncMutualFollows() }
        .onChange(of: scenePhase) { _, phase in
            // Polling on foreground rather than a CKQuerySubscription: the app has no
            // notification registration and no app delegate, so push would be new
            // plumbing for a latency win nobody would notice on a follower list.
            guard phase == .active else { return }
            Task { await syncMutualFollows() }
        }
    }

    // MARK: - Mutual follows

    private func syncMutualFollows() async {
        let result = await FollowService.syncMutualFollows(context: context)
        // Parked on the router rather than shown here: this runs unprompted, so the
        // right place for a failure is the Sharing screen's setup check, not an alert
        // over whatever the user actually opened the app to do.
        router.lastSweepFailure = result.failure
        guard !result.added.isEmpty else { return }
        router.newMutualFollows = result.added
    }

    /// Marks the notice seen so it doesn't reappear on the next foreground, and clears
    /// the banner.
    private func dismissMutualFollowNotice() {
        for user in router.newMutualFollows where !user.noticeAcknowledged {
            user.noticeAcknowledged = true
            user.markDirty()
        }
        try? context.save()
        router.newMutualFollows = []
    }

    /// Only offered for a single follower — see `MutualFollowBanner`. The soft delete
    /// this leaves behind is what stops the sweep re-adding them.
    private func undoMutualFollow() {
        for user in router.newMutualFollows {
            FollowService.unfollow(user, context: context)
        }
        router.newMutualFollows = []
    }

    private func hasWorkoutScheduledToday() -> Bool {
        let today = ScheduledWorkoutService.startOfDay(.now)
        let scheduled = (try? context.fetch(FetchDescriptor<ScheduledWorkout>())) ?? []
        return scheduled.contains { $0.deletedAt == nil && $0.date == today }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            MuscleCategory.self, Muscle.self,
            Equipment.self, WeightCombo.self,
            ExerciseCategory.self, Exercise.self,
        ], inMemory: true)
}
