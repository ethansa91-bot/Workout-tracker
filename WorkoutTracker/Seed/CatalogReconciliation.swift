import Foundation
import SwiftData

/// Removes duplicate seeded catalog rows left behind when two devices each seeded their
/// own copy before CloudKit merged them.
///
/// `CatalogSeedLoader` now refuses to insert a row whose deterministic id is already in
/// the store, which prevents *new* duplicates. It can't prevent the first-launch race:
/// seeding runs synchronously in `WorkoutTrackerApp.init()`, well before CloudKit's
/// initial import lands, so a fresh second device finds an empty store, seeds a full
/// catalog, and only then receives the first device's copy. And it does nothing at all
/// for devices already carrying duplicates from before that guard existed — which is
/// the situation any existing install is in.
///
/// So this runs after an import completes, groups each seeded type by `id`, keeps one
/// row, and re-points every relationship at the survivor before deleting the rest.
enum CatalogReconciliation {
    private static var hasRun = false

    /// Wires the one-shot pass to the first successful CloudKit import. Safe to call on
    /// every launch — it only ever schedules itself once per process.
    @MainActor
    static func runAfterNextImport(container: ModelContainer) {
        guard !hasRun else { return }
        CloudKitSyncMonitor.shared.onImportCompleted = {
            guard !hasRun else { return }
            hasRun = true
            run(context: container.mainContext)
        }
    }

    /// Deduplicates every seeded type. Each pass is independent, so a failure in one
    /// doesn't strand the others.
    @MainActor
    static func run(context: ModelContext) {
        var removed = 0
        removed += dedupe(MuscleCategory.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.muscles = union(survivor.muscles, duplicate.muscles)
        }
        removed += dedupe(ExerciseCategory.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.exercises = union(survivor.exercises, duplicate.exercises)
        }
        removed += dedupe(Muscle.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.categories = union(survivor.categories, duplicate.categories)
            survivor.exercisesStorage = union(survivor.exercisesStorage ?? [], duplicate.exercisesStorage ?? [])
        }
        removed += dedupe(Equipment.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.weightCombos = union(survivor.weightCombos, duplicate.weightCombos)
            survivor.exercisesStorage = union(survivor.exercisesStorage ?? [], duplicate.exercisesStorage ?? [])
            // These four were missing, and `dedupe` hard-deletes the loser — so SwiftData
            // nullified every one of them. That is how a perfectly good record lost its
            // equipment and reappeared as a phantom "No equipment" copy beside the new one
            // the runner then created under the surviving row. The `ExecutionType` and
            // `Exercise` passes below already do this; `Equipment` was the gap.
            for log in duplicate.setLogs ?? [] { log.equipment = survivor }
            for record in duplicate.personalRecords ?? [] { record.equipment = survivor }
            for entry in duplicate.personalRecordEntries ?? [] { entry.equipment = survivor }
            for item in duplicate.repSectionExercises ?? [] { item.preferredEquipment = survivor }
            for item in duplicate.timeSectionSteps ?? [] { item.preferredEquipment = survivor }
        }
        removed += dedupe(ExecutionType.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.exercisesStorage = union(survivor.exercisesStorage ?? [], duplicate.exercisesStorage ?? [])
            // Back-references from user data, for the same reason `Exercise` carries them
            // below: a logged set or a record pointing at the losing copy would otherwise
            // lose its execution type when that copy is deleted.
            for item in duplicate.repSectionExercises ?? [] { item.executionType = survivor }
            for item in duplicate.timeSectionSteps ?? [] { item.executionType = survivor }
            for item in duplicate.sectionExerciseEntries ?? [] { item.executionType = survivor }
            for item in duplicate.setLogs ?? [] { item.executionType = survivor }
            for item in duplicate.stepLogs ?? [] { item.executionType = survivor }
            for item in duplicate.personalRecords ?? [] { item.executionType = survivor }
            for item in duplicate.personalRecordEntries ?? [] { item.executionType = survivor }
        }
        removed += dedupe(WorkoutTag.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.workoutsStorage = union(survivor.workoutsStorage ?? [], duplicate.workoutsStorage ?? [])
            survivor.sectionsStorage = union(survivor.sectionsStorage ?? [], duplicate.sectionsStorage ?? [])
        }
        removed += dedupe(ProgressionGroup.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.stepsStorage = union(survivor.stepsStorage ?? [], duplicate.stepsStorage ?? [])
            // The higher of the two: a level reached on either copy was still reached.
            survivor.reachedLevel = max(survivor.reachedLevel, duplicate.reachedLevel)
        }
        removed += dedupe(ProgressionStep.self, context: context) { $0.id } merging: { _, _ in }
        removed += dedupe(WeightCombo.self, context: context) { $0.id } merging: { _, _ in }
        removed += dedupe(Exercise.self, context: context) { $0.id } merging: { survivor, duplicate in
            survivor.equipmentItems = union(survivor.equipmentItems, duplicate.equipmentItems)
            survivor.muscles = union(survivor.muscles, duplicate.muscles)
            survivor.categories = union(survivor.categories, duplicate.categories)
            // Back-references from user data. These are the ones that actually matter:
            // a workout or a logged set pointing at the losing copy would otherwise lose
            // its exercise entirely when that copy is deleted.
            for record in duplicate.personalRecords ?? [] { record.exercise = survivor }
            for item in duplicate.repSectionExercises ?? [] { item.exercise = survivor }
            for entry in duplicate.sectionExerciseEntries ?? [] { entry.exercise = survivor }
            for log in duplicate.setLogs ?? [] { log.exercise = survivor }
            for step in duplicate.timeSectionSteps ?? [] { step.exercise = survivor }
            for note in duplicate.exerciseSessionNotes ?? [] { note.exercise = survivor }
            // Both were missing. `dedupe` hard-deletes the loser, so SwiftData nullifies
            // these inverses — leaving a progression rung pointing at nothing, which is
            // precisely the orphan state that used to block deleting an exercise forever.
            for entry in duplicate.personalRecordEntries ?? [] { entry.exercise = survivor }
            for step in duplicate.progressionSteps ?? [] { step.exercise = survivor }
        }

        guard removed > 0 else { return }
        do {
            try context.save()
            print("CatalogReconciliation: removed \(removed) duplicate catalog rows")
        } catch {
            print("CatalogReconciliation: save failed: \(error)")
        }
    }

    /// Groups rows by id, keeps the oldest (by `updatedAt`), hands each loser to
    /// `merging` so its relationships can be moved over, then hard-deletes it.
    ///
    /// The delete is deliberately `context.delete` and not `SyncDeletion.delete`: a
    /// tombstone would leave the redundant row present-but-hidden and still syncing,
    /// which is the opposite of what removing a duplicate is for.
    private static func dedupe<T: PersistentModel & SyncableModel>(
        _ type: T.Type,
        context: ModelContext,
        id: (T) -> UUID,
        merging: (_ survivor: T, _ duplicate: T) -> Void
    ) -> Int {
        guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return 0 }
        let groups = Dictionary(grouping: rows, by: id)
        var removed = 0

        for (_, group) in groups where group.count > 1 {
            // Oldest wins, so every device independently picks the same survivor: the
            // row that was created first is the one both devices' imports agree on.
            let sorted = group.sorted { $0.updatedAt < $1.updatedAt }
            guard let survivor = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                merging(survivor, duplicate)
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    /// Concatenates two to-many relationships without repeating a model that is already
    /// present in both.
    private static func union<T: PersistentModel>(_ lhs: [T], _ rhs: [T]) -> [T] {
        var result = lhs
        for item in rhs where !result.contains(where: { $0.persistentModelID == item.persistentModelID }) {
            result.append(item)
        }
        return result
    }
}
