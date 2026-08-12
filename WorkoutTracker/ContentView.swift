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
        TabView {
            WorkoutListView()
                .tabItem { Label("My Workouts", systemImage: "list.bullet.rectangle") }

            LibraryHomeView()
                .tabItem { Label("Library", systemImage: "dumbbell.fill") }

            SessionHistoryListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            RecordsListView()
                .tabItem { Label("Records", systemImage: "trophy.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
