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
        // iOS shows only the first 4 tabItems directly, collapsing the rest into
        // an automatic "More" tab — so Schedule/My Workouts/Records/Settings (the
        // ones that must always stay directly visible, in this exact order, with
        // Settings last) occupy positions 0-3; Library/History fall into "More".
        TabView {
            ScheduleListView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            WorkoutListView()
                .tabItem { Label("My Workouts", systemImage: "list.bullet.rectangle") }

            RecordsListView()
                .tabItem { Label("Records", systemImage: "trophy.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }

            LibraryHomeView()
                .tabItem { Label("Library", systemImage: "dumbbell.fill") }

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
