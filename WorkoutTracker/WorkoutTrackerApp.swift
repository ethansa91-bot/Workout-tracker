//
//  WorkoutTrackerApp.swift
//  WorkoutTracker
//
//  Created by Ethan Winiger on 09/08/26.
//

import SwiftUI
import SwiftData

@main
struct WorkoutTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MuscleCategory.self,
            Muscle.self,
            Equipment.self,
            WeightCombo.self,
            ExerciseCategory.self,
            Exercise.self,
            Workout.self,
            WorkoutBlock.self,
            TimeBlockStep.self,
            RepBlockExercise.self,
            WorkoutSession.self,
            StepLog.self,
            SetLog.self,
            PersonalRecord.self,
        ])
        // cloudKitDatabase: .none is required, not optional — SwiftData otherwise tries to
        // prepare the store for CloudKit sync, which rejects @Attribute(.unique) fields
        // (every model here has one on `id`). The Simulator is lenient about this; real
        // devices enforce it strictly, which is why this only crashes on-device. We don't
        // want CloudKit involved anyway — sync goes through Supabase, not iCloud.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        AppearanceConfiguration.apply()
        SeedDataLoader.seedIfNeeded(context: sharedModelContainer.mainContext)
        MuscleTaxonomyMigration.migrateIfNeeded(context: sharedModelContainer.mainContext)
        FavoriteExercisesImport.importIfNeeded(context: sharedModelContainer.mainContext)
        FavoriteExercisesCorrection.correctIfNeeded(context: sharedModelContainer.mainContext)
        GetReadyStepMigration.migrateIfNeeded(context: sharedModelContainer.mainContext)
        ExerciseImageMigration.migrateIfNeeded(context: sharedModelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
