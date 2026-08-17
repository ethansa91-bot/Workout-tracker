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
    @State private var selectedTab: Tab = .schedule

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

            RecordsListView()
                .tabItem { Label("Records", systemImage: "trophy.fill") }
                .tag(Tab.records)

            SessionHistoryListView()
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
