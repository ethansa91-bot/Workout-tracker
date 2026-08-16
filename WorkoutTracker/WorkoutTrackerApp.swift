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
            WorkoutSection.self,
            TimeSectionStep.self,
            RepSectionExercise.self,
            SectionExerciseEntry.self,
            WorkoutSession.self,
            StepLog.self,
            SetLog.self,
            ExerciseSessionNote.self,
            PersonalRecord.self,
            RecurringWorkoutSchedule.self,
            ScheduledWorkout.self,
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
        let context = sharedModelContainer.mainContext

        if SeedDataLoader.hasSeeded {
            // Device already has a catalog — from the old multi-step pipeline, or from
            // CatalogSeedLoader (which pre-marks every one of these flags done, making
            // this whole branch a no-op there). Kept exactly as-is so any device still
            // mid-pipeline keeps advancing normally; nothing here is ever run twice.
            SeedDataLoader.seedIfNeeded(context: context)
            MuscleTaxonomyMigration.migrateIfNeeded(context: context)
            FavoriteExercisesImport.importIfNeeded(context: context)
            FavoriteExercisesCorrection.correctIfNeeded(context: context)
            ExerciseImageMigration.migrateIfNeeded(context: context)
            ExerciseImageRemovalMigration.migrateIfNeeded(context: context)
            WgerCatalogMigration.migrateIfNeeded(context: context)
            WgerCatalogCorrection.correctIfNeeded(context: context)
            WgerCategoryRevert.revertIfNeeded(context: context)
            EquipmentHomeGymMigration.migrateIfNeeded(context: context)
            EquipmentWeightedMigration.migrateIfNeeded(context: context)
            ExerciseEquipmentMigration.migrateIfNeeded(context: context)
            WgerNoPhotoCleanup.migrateIfNeeded(context: context)
            PersonalExerciseImport.importIfNeeded(context: context)
            ExerciseReviewFavoritesImport.importIfNeeded(context: context)
            PersonalEquipmentUpdate.migrateIfNeeded(context: context)
        } else {
            // Fresh install — one consolidated catalog load (see CatalogSeedLoader)
            // instead of the legacy chain above, which the loader marks fully done so
            // no future launch on this device ever runs it.
            CatalogSeedLoader.seedIfNeeded(context: context)
            for key in Self.legacyMigrationFlagKeys {
                UserDefaults.standard.set(true, forKey: key)
            }
        }

        GetReadyStepMigration.migrateIfNeeded(context: context)
    }

    /// Flags for every legacy migration superseded by `CatalogSeedLoader` on a fresh
    /// install — pre-marked done so a device seeded this way never runs them later.
    /// Not private — `DataResetService` replays this same "fresh install" bookkeeping
    /// after a manual reset, so a reset device behaves identically to a real one.
    static let legacyMigrationFlagKeys = [
        "migration.muscleTaxonomyV1",
        "import.favoriteExercisesV1",
        "import.favoriteExercisesCorrectionV1",
        "migration.exerciseImagesV1",
        "migration.exerciseImageRemovalV1",
        "migration.wgerCatalogV1",
        "migration.wgerCatalogCorrectionV1",
        "migration.wgerCategoryRevertV1",
        "migration.equipmentHomeGymV1",
        "migration.equipmentWeightedV1",
        "migration.exerciseEquipmentV1",
        "migration.wgerNoPhotoCleanupV1",
        "import.personalExercisesV1",
        "import.exerciseReviewFavoritesV1",
        "migration.personalEquipmentUpdateV1",
    ]

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
