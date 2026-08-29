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
            PersonalRecordEntry.self,
            RecurringWorkoutSchedule.self,
            ScheduledWorkout.self,
            FollowedUser.self,
        ])
        // Syncs every model in the schema across the user's own devices via iCloud.
        // Requires the WorkoutTracker.entitlements iCloud/CloudKit capability and a
        // matching container identifier registered on the Apple Developer account.
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(CloudKitContainer.identifier)
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            ContainerStatus.record(isCloudEnabled: true, failure: nil)
            return container
        } catch {
            // CloudKit setup fails for ordinary, recoverable reasons — no iCloud
            // account, no network on first run, a schema not yet deployed to the
            // Production environment. Crashing here would make the app unusable
            // offline and unlaunchable on TestFlight, so fall back to a local-only
            // store instead. Both configurations resolve to the same on-disk store
            // URL, so no data is lost and nothing starts from scratch.
            let nsError = error as NSError
            let detail = """
                CloudKit ModelContainer unavailable, falling back to local-only: \(error)
                NSError domain: \(nsError.domain), code: \(nsError.code)
                userInfo: \(nsError.userInfo)
                underlying: \(nsError.userInfo[NSUnderlyingErrorKey].map { String(describing: $0) } ?? "none")
                """
            print(detail)

            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                ContainerStatus.record(isCloudEnabled: false, failure: nsError)
                return container
            } catch {
                // The local store itself is unusable — there is no degraded mode left.
                fatalError("Could not create ModelContainer (cloud or local): \(error)")
            }
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

        // Outside the fresh-install branch: a device that already picked "lb" needs the
        // switch too, not just brand-new installs.
        WeightUnitKgMigration.migrateIfNeeded()

        // Seeding above runs before CloudKit's first import can land, so a second device
        // seeds its own catalog and then receives the first device's. This cleans up the
        // resulting duplicates once that import completes — and repairs devices that
        // already have them.
        if ContainerStatus.isCloudEnabled {
            MainActor.assumeIsolated {
                CatalogReconciliation.runAfterNextImport(container: sharedModelContainer)
            }
        }

        // Opt-in CloudKit schema tooling, both on a device signed into iCloud.
        //
        // CK_VALIDATE=1 reports exactly which entity or property CloudKit can't mirror —
        // the detail an export `partialFailure` withholds, and it creates nothing.
        //
        // CK_INIT_SCHEMA=1 creates every record type and field in the Development
        // environment. Run this before any TestFlight build that added a model, then
        // deploy to Production; see CloudKitSchemaValidator for why auto-creation alone
        // silently misses types you never happen to write.
        //
        // Debug-only; `initializeCloudKitSchema` must never ship.
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CK_INIT_SCHEMA"] == "1" || environment["CK_VALIDATE"] == "1" {
            // Creating wins if both are set — it's the strictly larger operation, and it
            // reports everything the dry run would have.
            let createsSchema = environment["CK_INIT_SCHEMA"] == "1"
            // Off the main thread: this does real network work and takes tens of seconds,
            // which would trip the launch watchdog if run inline here.
            Thread.detachNewThread { CloudKitSchemaValidator.run(createsSchema: createsSchema) }
        }
        #endif
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

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Share links land here. The router only stores the code; presenting it
                // is `ContentView`'s job, so a link works from whichever tab is open.
                .onOpenURL { SharingRouter.shared.handle($0) }
        }
        .modelContainer(sharedModelContainer)
        // Backgrounding ends any claim on speech and the audio session. Without this a
        // workout left running in the background kept the synthesizer alive and the
        // session active — and with it, other apps' audio ducked.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { SpeechAnnouncer.teardown() }
        }
    }
}
