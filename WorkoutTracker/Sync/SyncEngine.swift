import Foundation
import SwiftData

/// Generic pull/push written once against `CatalogSyncAdapter`, instead of once per
/// table.
enum CatalogSync {
    static func pull<A: CatalogSyncAdapter>(_ adapter: A.Type, since watermark: Date?, context: ModelContext) async throws {
        let dtos: [A.DTO] = try await SupabaseREST.fetchUpdated(table: A.tableName, since: watermark)
        for dto in dtos {
            let id = A.id(of: dto)
            let remoteUpdatedAt = A.updatedAt(of: dto)
            if let existing = A.fetchLocal(id: id, context: context) {
                // Last-write-wins: only overwrite local state if the remote row is newer.
                guard remoteUpdatedAt > existing.updatedAt else { continue }
                if let deletedAt = A.deletedAt(of: dto) {
                    existing.deletedAt = deletedAt
                } else {
                    A.applyRemote(dto, to: existing, context: context)
                }
                existing.updatedAt = remoteUpdatedAt
                existing.isDirty = false
                existing.remoteSyncedAt = .now
            } else if A.deletedAt(of: dto) == nil {
                let model = A.insertLocal(from: dto, context: context)
                model.updatedAt = remoteUpdatedAt
                model.isDirty = false
                model.remoteSyncedAt = .now
            }
        }
    }

    static func push<A: CatalogSyncAdapter>(_ adapter: A.Type, dirtyModels: [A.Model]) async throws {
        guard !dirtyModels.isEmpty else { return }
        let dtos = dirtyModels.map(A.dto)
        try await SupabaseREST.upsert(table: A.tableName, rows: dtos)
        for model in dirtyModels {
            model.isDirty = false
            model.remoteSyncedAt = .now
        }
    }
}

/// Top-level sync orchestration. Local-first: every read/write in the app hits
/// SwiftData directly — this type is only ever invoked from explicit sync actions
/// (the per-item "sync this" button, "sync everything", or the silent
/// updates-available check), never automatically in the background.
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()
    private init() {}

    /// Supabase sync is disconnected for now — backup/sync between devices is moving
    /// to CloudKit once Apple Developer Program access is set up. Every public entry
    /// point below is a no-op while this is `true`; flip it back to restore Supabase
    /// sync without touching anything else in this file.
    static let isDisabled = true

    /// Silent watermark check — never syncs by itself. True if Supabase has changes
    /// this device hasn't pulled yet, which the UI turns into an "Updates available —
    /// sync now?" prompt.
    func remoteHasUpdates() async -> Bool {
        guard !Self.isDisabled else { return false }
        guard NetworkReachability.shared.isOnline else { return false }
        guard let watermarks = try? await SupabaseREST.fetchWatermarks() else { return false }
        guard let lastSyncedAt = SyncState.lastSyncedAt else { return !watermarks.isEmpty }
        return watermarks.values.contains { $0 > lastSyncedAt }
    }

    /// Pushes one just-created/edited equipment item, plus any never-synced weight
    /// combos on it. Used by the per-creation "sync this" button.
    func syncSingle(equipment: Equipment) async throws {
        guard !Self.isDisabled else { return }
        try await CatalogSync.push(EquipmentSyncAdapter.self, dirtyModels: [equipment])
        try await CatalogSync.push(WeightComboSyncAdapter.self, dirtyModels: equipment.weightCombos.filter(\.isDirty))
    }

    /// Pushes one just-created/edited exercise (and any never-synced equipment it's
    /// attached to) plus its full current muscle/category/equipment tag sets.
    func syncSingle(exercise: Exercise) async throws {
        guard !Self.isDisabled else { return }
        for equipment in exercise.equipmentItems where equipment.remoteSyncedAt == nil {
            try await syncSingle(equipment: equipment)
        }
        try await CatalogSync.push(ExerciseSyncAdapter.self, dirtyModels: [exercise])
        try await JoinSync.pushExerciseMuscles(for: exercise)
        try await JoinSync.pushExerciseCategories(for: exercise)
        try await JoinSync.pushExerciseEquipment(for: exercise)
    }

    /// Full bidirectional diff across catalog + workouts + session history: pull
    /// everything changed remotely since the last sync (parent tables before
    /// children, so foreign keys always resolve), then push everything dirty locally
    /// in the same order, then replace every join association set. Safe to retry —
    /// every step is idempotent by id.
    func syncAll(context: ModelContext) async throws {
        guard !Self.isDisabled else { return }
        let watermark = SyncState.lastSyncedAt

        try await CatalogSync.pull(MuscleCategorySyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(MuscleSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(EquipmentSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(WeightComboSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(ExerciseCategorySyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(ExerciseSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(PersonalRecordSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(WorkoutSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(RecurringWorkoutScheduleSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(ScheduledWorkoutSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(WorkoutSectionSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(TimeSectionStepSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(RepSectionExerciseSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(WorkoutSessionSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(StepLogSyncAdapter.self, since: watermark, context: context)
        try await CatalogSync.pull(SetLogSyncAdapter.self, since: watermark, context: context)

        try await pushDirty(MuscleCategorySyncAdapter.self, context: context)
        try await pushDirty(MuscleSyncAdapter.self, context: context)
        try await pushDirty(EquipmentSyncAdapter.self, context: context)
        try await pushDirty(WeightComboSyncAdapter.self, context: context)
        try await pushDirty(ExerciseCategorySyncAdapter.self, context: context)
        try await pushDirty(ExerciseSyncAdapter.self, context: context)
        try await pushDirty(PersonalRecordSyncAdapter.self, context: context)
        try await pushDirty(WorkoutSyncAdapter.self, context: context)
        try await pushDirty(RecurringWorkoutScheduleSyncAdapter.self, context: context)
        try await pushDirty(ScheduledWorkoutSyncAdapter.self, context: context)
        try await pushDirty(WorkoutSectionSyncAdapter.self, context: context)
        try await pushDirty(TimeSectionStepSyncAdapter.self, context: context)
        try await pushDirty(RepSectionExerciseSyncAdapter.self, context: context)
        try await pushDirty(WorkoutSessionSyncAdapter.self, context: context)
        try await pushDirty(StepLogSyncAdapter.self, context: context)
        try await pushDirty(SetLogSyncAdapter.self, context: context)

        try await pushAllJoinAssociations(context: context)

        SyncState.lastSyncedAt = .now
    }

    private func pushDirty<A: CatalogSyncAdapter>(_ adapter: A.Type, context: ModelContext) async throws {
        let all = try context.fetch(FetchDescriptor<A.Model>())
        try await CatalogSync.push(adapter, dirtyModels: all.filter(\.isDirty))
    }

    private func pushAllJoinAssociations(context: ModelContext) async throws {
        for muscle in try context.fetch(FetchDescriptor<Muscle>()) {
            try await JoinSync.pushMuscleCategories(for: muscle)
        }
        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            try await JoinSync.pushExerciseMuscles(for: exercise)
            try await JoinSync.pushExerciseCategories(for: exercise)
            try await JoinSync.pushExerciseEquipment(for: exercise)
        }
    }
}
