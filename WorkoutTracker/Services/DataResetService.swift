import Foundation
import SwiftData

/// Wipes every locally-stored row and reseeds the starter catalog (muscles, equipment,
/// exercises) fresh from `catalog.json` — a full factory reset, e.g. for recovering from
/// corrupted/inconsistent local state. Irreversible: everything not part of the seed
/// catalog (custom exercises, workouts, sessions, logs, notes, schedules, records) is
/// gone for good once this runs.
enum DataResetService {
    static func resetAndReseed(context: ModelContext) throws {
        // Fetch-then-delete rather than the bulk `context.delete(model:)` API — the bulk
        // form operates below the normal object graph and doesn't reliably honor
        // cascade/inverse relationships here, tripping a "mandatory nullify inverse"
        // constraint trigger. Deleting fetched objects one at a time goes through
        // SwiftData's standard relationship-aware deletion path instead.
        try deleteAll(SetLog.self, context: context)
        try deleteAll(StepLog.self, context: context)
        try deleteAll(ExerciseSessionNote.self, context: context)
        try deleteAll(WorkoutSession.self, context: context)
        try deleteAll(PersonalRecord.self, context: context)
        try deleteAll(ScheduledWorkout.self, context: context)
        try deleteAll(RecurringWorkoutSchedule.self, context: context)
        try deleteAll(RepSectionExercise.self, context: context)
        try deleteAll(TimeSectionStep.self, context: context)
        try deleteAll(SectionExerciseEntry.self, context: context)
        try deleteAll(WorkoutSection.self, context: context)
        try deleteAll(Workout.self, context: context)
        try deleteAll(Exercise.self, context: context)
        try deleteAll(WeightCombo.self, context: context)
        try deleteAll(Equipment.self, context: context)
        try deleteAll(ExerciseCategory.self, context: context)
        try deleteAll(Muscle.self, context: context)
        try deleteAll(MuscleCategory.self, context: context)
        try context.save()

        // Mirrors CatalogSeedLoader's fresh-install path, but calls the throwing `seed`
        // directly rather than `seedIfNeeded` — that variant swallows errors (fine for
        // its silent best-effort use at app launch, wrong here: a reset that silently
        // deletes everything and then fails to reseed must not look like it succeeded).
        UserDefaults.standard.removeObject(forKey: SeedDataLoader.seededFlagKey)
        try CatalogSeedLoader.seed(context: context)
        for key in WorkoutTrackerApp.legacyMigrationFlagKeys {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}
