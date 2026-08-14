//
//  ContentView.swift
//  WorkoutTracker
//
//  Created by Ethan Winiger on 09/08/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        // iOS only collapses tabs into an automatic "More" tab once there are more
        // than 5 — five items (Library folded into My Workouts as a horizontal
        // pane selector instead of its own tab) all show directly, no "More".
        TabView {
            ScheduleListView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            WorkoutListView()
                .tabItem { Label("My Workouts", systemImage: "list.bullet.rectangle") }

            RecordsListView()
                .tabItem { Label("Records", systemImage: "trophy.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }

            SessionHistoryListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(Color.appAccent)
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
