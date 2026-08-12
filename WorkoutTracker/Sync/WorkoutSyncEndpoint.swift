import Foundation
import SwiftData

// MARK: - Workout / session DTOs
//
// Same rule as the catalog DTOs in SyncEndpoint.swift: every optional field gets an
// explicit `encode(to:)` using plain `encode(_:forKey:)` rather than the
// auto-synthesized `encodeIfPresent`, so a bulk upsert never produces rows with
// different key sets (PostgREST's PGRST102 "all object keys must match").

struct WorkoutDTO: Codable {
    let id: UUID
    let name: String
    let notes: String?
    let createdAt: Date
    let clonedFromWorkoutId: UUID?
    let kind: String
    let isArchived: Bool
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(notes, forKey: .notes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(clonedFromWorkoutId, forKey: .clonedFromWorkoutId)
        try c.encode(kind, forKey: .kind)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct WorkoutBlockDTO: Codable {
    let id: UUID
    let workoutId: UUID
    let sortOrder: Int
    let blockType: String
    let name: String?
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(blockType, forKey: .blockType)
        try c.encode(name, forKey: .name)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct TimeBlockStepDTO: Codable {
    let id: UUID
    let workoutBlockId: UUID
    let sortOrder: Int
    let stepType: String
    let exerciseId: UUID?
    let durationSeconds: Int
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutBlockId, forKey: .workoutBlockId)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(stepType, forKey: .stepType)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct RepBlockExerciseDTO: Codable {
    let id: UUID
    let workoutBlockId: UUID
    let sortOrder: Int
    let exerciseId: UUID?
    let targetSets: Int
    let customRestSeconds: Int?
    let trackingMode: String
    let headStartSeconds: Int
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutBlockId, forKey: .workoutBlockId)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(targetSets, forKey: .targetSets)
        try c.encode(customRestSeconds, forKey: .customRestSeconds)
        try c.encode(trackingMode, forKey: .trackingMode)
        try c.encode(headStartSeconds, forKey: .headStartSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct WorkoutSessionDTO: Codable {
    let id: UUID
    let workoutId: UUID
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let accumulatedActiveSeconds: Double
    let lastResumedAt: Date?
    let currentBlockIndex: Int
    let currentStepIndex: Int?
    let currentExerciseIndex: Int?
    let currentSetIndex: Int?
    let supersededBySessionId: UUID?
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(status, forKey: .status)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(accumulatedActiveSeconds, forKey: .accumulatedActiveSeconds)
        try c.encode(lastResumedAt, forKey: .lastResumedAt)
        try c.encode(currentBlockIndex, forKey: .currentBlockIndex)
        try c.encode(currentStepIndex, forKey: .currentStepIndex)
        try c.encode(currentExerciseIndex, forKey: .currentExerciseIndex)
        try c.encode(currentSetIndex, forKey: .currentSetIndex)
        try c.encode(supersededBySessionId, forKey: .supersededBySessionId)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct StepLogDTO: Codable {
    let id: UUID
    let sessionId: UUID
    let timeBlockStepId: UUID?
    let stepExerciseNameSnapshot: String?
    let plannedDurationSeconds: Int
    let actualDurationSeconds: Int
    let outcome: String
    let loggedAt: Date
    let sortOrder: Int
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(timeBlockStepId, forKey: .timeBlockStepId)
        try c.encode(stepExerciseNameSnapshot, forKey: .stepExerciseNameSnapshot)
        try c.encode(plannedDurationSeconds, forKey: .plannedDurationSeconds)
        try c.encode(actualDurationSeconds, forKey: .actualDurationSeconds)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(loggedAt, forKey: .loggedAt)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct SetLogDTO: Codable {
    let id: UUID
    let sessionId: UUID
    let repBlockExerciseId: UUID?
    let exerciseId: UUID?
    let exerciseNameSnapshot: String?
    let setIndex: Int
    let reps: Int
    let weight: Double
    let weightUnit: String
    let holdSeconds: Int?
    let loggedAt: Date
    let isCancelled: Bool
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(repBlockExerciseId, forKey: .repBlockExerciseId)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(exerciseNameSnapshot, forKey: .exerciseNameSnapshot)
        try c.encode(setIndex, forKey: .setIndex)
        try c.encode(reps, forKey: .reps)
        try c.encode(weight, forKey: .weight)
        try c.encode(weightUnit, forKey: .weightUnit)
        try c.encode(holdSeconds, forKey: .holdSeconds)
        try c.encode(loggedAt, forKey: .loggedAt)
        try c.encode(isCancelled, forKey: .isCancelled)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct PersonalRecordDTO: Codable {
    let id: UUID
    let exerciseId: UUID?
    let trackingMode: String
    let weight: Double?
    let reps: Int?
    let holdSeconds: Int?
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(trackingMode, forKey: .trackingMode)
        try c.encode(weight, forKey: .weight)
        try c.encode(reps, forKey: .reps)
        try c.encode(holdSeconds, forKey: .holdSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

// MARK: - Adapters

enum WorkoutSyncAdapter: CatalogSyncAdapter {
    static let tableName = "workouts"
    static func dto(from model: Workout) -> WorkoutDTO {
        WorkoutDTO(id: model.id, name: model.name, notes: model.notes, createdAt: model.createdAt, clonedFromWorkoutId: model.clonedFromWorkoutId, kind: model.kindRaw, isArchived: model.isArchived, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: WorkoutDTO) -> UUID { dto.id }
    static func updatedAt(of dto: WorkoutDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: WorkoutDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: WorkoutDTO, context: ModelContext) -> Workout {
        let model = Workout(id: dto.id, name: dto.name, notes: dto.notes, clonedFromWorkoutId: dto.clonedFromWorkoutId, kind: WorkoutKind(rawValue: dto.kind) ?? .personalized)
        model.createdAt = dto.createdAt
        model.isArchived = dto.isArchived
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: WorkoutDTO, to model: Workout, context: ModelContext) {
        model.name = dto.name
        model.notes = dto.notes
        model.clonedFromWorkoutId = dto.clonedFromWorkoutId
        model.kindRaw = dto.kind
        model.isArchived = dto.isArchived
    }
}

enum WorkoutBlockSyncAdapter: CatalogSyncAdapter {
    static let tableName = "workout_blocks"
    static func dto(from model: WorkoutBlock) -> WorkoutBlockDTO {
        WorkoutBlockDTO(id: model.id, workoutId: model.workout?.id ?? UUID(), sortOrder: model.sortOrder, blockType: model.blockTypeRaw, name: model.name, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: WorkoutBlockDTO) -> UUID { dto.id }
    static func updatedAt(of dto: WorkoutBlockDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: WorkoutBlockDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> WorkoutBlock? {
        var descriptor = FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: WorkoutBlockDTO, context: ModelContext) -> WorkoutBlock {
        let workout = WorkoutSyncAdapter.fetchLocal(id: dto.workoutId, context: context)
        let model = WorkoutBlock(id: dto.id, workout: workout, sortOrder: dto.sortOrder, blockType: WorkoutBlockType(rawValue: dto.blockType) ?? .time, name: dto.name)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: WorkoutBlockDTO, to model: WorkoutBlock, context: ModelContext) {
        model.sortOrder = dto.sortOrder
        model.blockTypeRaw = dto.blockType
        model.name = dto.name
        if model.workout?.id != dto.workoutId {
            model.workout = WorkoutSyncAdapter.fetchLocal(id: dto.workoutId, context: context)
        }
    }
}

enum TimeBlockStepSyncAdapter: CatalogSyncAdapter {
    static let tableName = "time_block_steps"
    static func dto(from model: TimeBlockStep) -> TimeBlockStepDTO {
        TimeBlockStepDTO(id: model.id, workoutBlockId: model.block?.id ?? UUID(), sortOrder: model.sortOrder, stepType: model.stepTypeRaw, exerciseId: model.exercise?.id, durationSeconds: model.durationSeconds, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: TimeBlockStepDTO) -> UUID { dto.id }
    static func updatedAt(of dto: TimeBlockStepDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: TimeBlockStepDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> TimeBlockStep? {
        var descriptor = FetchDescriptor<TimeBlockStep>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: TimeBlockStepDTO, context: ModelContext) -> TimeBlockStep {
        let block = WorkoutBlockSyncAdapter.fetchLocal(id: dto.workoutBlockId, context: context)
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = TimeBlockStep(id: dto.id, block: block, sortOrder: dto.sortOrder, stepType: TimeStepType(rawValue: dto.stepType) ?? .exercise, exercise: exercise, durationSeconds: dto.durationSeconds)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: TimeBlockStepDTO, to model: TimeBlockStep, context: ModelContext) {
        model.sortOrder = dto.sortOrder
        model.stepTypeRaw = dto.stepType
        model.durationSeconds = dto.durationSeconds
        if model.exercise?.id != dto.exerciseId {
            model.exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
        if model.block?.id != dto.workoutBlockId {
            model.block = WorkoutBlockSyncAdapter.fetchLocal(id: dto.workoutBlockId, context: context)
        }
    }
}

enum RepBlockExerciseSyncAdapter: CatalogSyncAdapter {
    static let tableName = "rep_block_exercises"
    static func dto(from model: RepBlockExercise) -> RepBlockExerciseDTO {
        RepBlockExerciseDTO(id: model.id, workoutBlockId: model.block?.id ?? UUID(), sortOrder: model.sortOrder, exerciseId: model.exercise?.id, targetSets: model.targetSets, customRestSeconds: model.customRestSeconds, trackingMode: model.trackingModeRaw, headStartSeconds: model.headStartSeconds, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: RepBlockExerciseDTO) -> UUID { dto.id }
    static func updatedAt(of dto: RepBlockExerciseDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: RepBlockExerciseDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> RepBlockExercise? {
        var descriptor = FetchDescriptor<RepBlockExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: RepBlockExerciseDTO, context: ModelContext) -> RepBlockExercise {
        let block = WorkoutBlockSyncAdapter.fetchLocal(id: dto.workoutBlockId, context: context)
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = RepBlockExercise(id: dto.id, block: block, sortOrder: dto.sortOrder, exercise: exercise, targetSets: dto.targetSets, customRestSeconds: dto.customRestSeconds, trackingMode: RepExerciseTrackingMode(rawValue: dto.trackingMode) ?? .repsWeight, headStartSeconds: dto.headStartSeconds)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: RepBlockExerciseDTO, to model: RepBlockExercise, context: ModelContext) {
        model.sortOrder = dto.sortOrder
        model.targetSets = dto.targetSets
        model.customRestSeconds = dto.customRestSeconds
        model.trackingModeRaw = dto.trackingMode
        model.headStartSeconds = dto.headStartSeconds
        if model.exercise?.id != dto.exerciseId {
            model.exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
        if model.block?.id != dto.workoutBlockId {
            model.block = WorkoutBlockSyncAdapter.fetchLocal(id: dto.workoutBlockId, context: context)
        }
    }
}

enum WorkoutSessionSyncAdapter: CatalogSyncAdapter {
    static let tableName = "workout_sessions"
    static func dto(from model: WorkoutSession) -> WorkoutSessionDTO {
        WorkoutSessionDTO(
            id: model.id, workoutId: model.workout?.id ?? UUID(), status: model.statusRaw,
            startedAt: model.startedAt, endedAt: model.endedAt,
            accumulatedActiveSeconds: model.accumulatedActiveSeconds, lastResumedAt: model.lastResumedAt,
            currentBlockIndex: model.currentBlockIndex, currentStepIndex: model.currentStepIndex,
            currentExerciseIndex: model.currentExerciseIndex, currentSetIndex: model.currentSetIndex,
            supersededBySessionId: model.supersededBySessionId,
            updatedAt: model.updatedAt, deletedAt: model.deletedAt
        )
    }
    static func id(of dto: WorkoutSessionDTO) -> UUID { dto.id }
    static func updatedAt(of dto: WorkoutSessionDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: WorkoutSessionDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: WorkoutSessionDTO, context: ModelContext) -> WorkoutSession {
        let workout = WorkoutSyncAdapter.fetchLocal(id: dto.workoutId, context: context)
        let model = WorkoutSession(id: dto.id, workout: workout)
        apply(dto, to: model)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: WorkoutSessionDTO, to model: WorkoutSession, context: ModelContext) {
        apply(dto, to: model)
        if model.workout?.id != dto.workoutId {
            model.workout = WorkoutSyncAdapter.fetchLocal(id: dto.workoutId, context: context)
        }
    }
    private static func apply(_ dto: WorkoutSessionDTO, to model: WorkoutSession) {
        model.statusRaw = dto.status
        model.startedAt = dto.startedAt
        model.endedAt = dto.endedAt
        model.accumulatedActiveSeconds = dto.accumulatedActiveSeconds
        model.lastResumedAt = dto.lastResumedAt
        model.currentBlockIndex = dto.currentBlockIndex
        model.currentStepIndex = dto.currentStepIndex
        model.currentExerciseIndex = dto.currentExerciseIndex
        model.currentSetIndex = dto.currentSetIndex
        model.supersededBySessionId = dto.supersededBySessionId
    }
}

enum StepLogSyncAdapter: CatalogSyncAdapter {
    static let tableName = "step_logs"
    static func dto(from model: StepLog) -> StepLogDTO {
        StepLogDTO(
            id: model.id, sessionId: model.session?.id ?? UUID(), timeBlockStepId: model.timeBlockStep?.id,
            stepExerciseNameSnapshot: model.stepExerciseNameSnapshot, plannedDurationSeconds: model.plannedDurationSeconds,
            actualDurationSeconds: model.actualDurationSeconds, outcome: model.outcomeRaw, loggedAt: model.loggedAt,
            sortOrder: model.sortOrder, updatedAt: model.updatedAt, deletedAt: model.deletedAt
        )
    }
    static func id(of dto: StepLogDTO) -> UUID { dto.id }
    static func updatedAt(of dto: StepLogDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: StepLogDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> StepLog? {
        var descriptor = FetchDescriptor<StepLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: StepLogDTO, context: ModelContext) -> StepLog {
        let session = WorkoutSessionSyncAdapter.fetchLocal(id: dto.sessionId, context: context)
        let step = dto.timeBlockStepId.flatMap { TimeBlockStepSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = StepLog(
            id: dto.id, session: session, timeBlockStep: step,
            stepExerciseNameSnapshot: dto.stepExerciseNameSnapshot, plannedDurationSeconds: dto.plannedDurationSeconds,
            actualDurationSeconds: dto.actualDurationSeconds, outcome: StepOutcome(rawValue: dto.outcome) ?? .completed,
            sortOrder: dto.sortOrder
        )
        model.loggedAt = dto.loggedAt
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: StepLogDTO, to model: StepLog, context: ModelContext) {
        model.stepExerciseNameSnapshot = dto.stepExerciseNameSnapshot
        model.plannedDurationSeconds = dto.plannedDurationSeconds
        model.actualDurationSeconds = dto.actualDurationSeconds
        model.outcomeRaw = dto.outcome
        model.loggedAt = dto.loggedAt
        model.sortOrder = dto.sortOrder
        if model.session?.id != dto.sessionId {
            model.session = WorkoutSessionSyncAdapter.fetchLocal(id: dto.sessionId, context: context)
        }
        if model.timeBlockStep?.id != dto.timeBlockStepId {
            model.timeBlockStep = dto.timeBlockStepId.flatMap { TimeBlockStepSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}

enum SetLogSyncAdapter: CatalogSyncAdapter {
    static let tableName = "set_logs"
    static func dto(from model: SetLog) -> SetLogDTO {
        SetLogDTO(
            id: model.id, sessionId: model.session?.id ?? UUID(), repBlockExerciseId: model.repBlockExercise?.id,
            exerciseId: model.exercise?.id, exerciseNameSnapshot: model.exerciseNameSnapshot, setIndex: model.setIndex,
            reps: model.reps, weight: model.weight, weightUnit: model.weightUnit, holdSeconds: model.holdSeconds,
            loggedAt: model.loggedAt, isCancelled: model.isCancelled, updatedAt: model.updatedAt, deletedAt: model.deletedAt
        )
    }
    static func id(of dto: SetLogDTO) -> UUID { dto.id }
    static func updatedAt(of dto: SetLogDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: SetLogDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> SetLog? {
        var descriptor = FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: SetLogDTO, context: ModelContext) -> SetLog {
        let session = WorkoutSessionSyncAdapter.fetchLocal(id: dto.sessionId, context: context)
        let repEntry = dto.repBlockExerciseId.flatMap { RepBlockExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = SetLog(
            id: dto.id, session: session, repBlockExercise: repEntry, exercise: exercise,
            exerciseNameSnapshot: dto.exerciseNameSnapshot, setIndex: dto.setIndex, reps: dto.reps,
            weight: dto.weight, weightUnit: dto.weightUnit, holdSeconds: dto.holdSeconds, isCancelled: dto.isCancelled
        )
        model.loggedAt = dto.loggedAt
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: SetLogDTO, to model: SetLog, context: ModelContext) {
        model.setIndex = dto.setIndex
        model.reps = dto.reps
        model.weight = dto.weight
        model.weightUnit = dto.weightUnit
        model.holdSeconds = dto.holdSeconds
        model.loggedAt = dto.loggedAt
        model.isCancelled = dto.isCancelled
        model.exerciseNameSnapshot = dto.exerciseNameSnapshot
        if model.session?.id != dto.sessionId {
            model.session = WorkoutSessionSyncAdapter.fetchLocal(id: dto.sessionId, context: context)
        }
        if model.repBlockExercise?.id != dto.repBlockExerciseId {
            model.repBlockExercise = dto.repBlockExerciseId.flatMap { RepBlockExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
        if model.exercise?.id != dto.exerciseId {
            model.exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}

enum PersonalRecordSyncAdapter: CatalogSyncAdapter {
    static let tableName = "personal_records"
    static func dto(from model: PersonalRecord) -> PersonalRecordDTO {
        PersonalRecordDTO(id: model.id, exerciseId: model.exercise?.id, trackingMode: model.trackingModeRaw, weight: model.weight, reps: model.reps, holdSeconds: model.holdSeconds, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: PersonalRecordDTO) -> UUID { dto.id }
    static func updatedAt(of dto: PersonalRecordDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: PersonalRecordDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> PersonalRecord? {
        var descriptor = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: PersonalRecordDTO, context: ModelContext) -> PersonalRecord {
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = PersonalRecord(id: dto.id, exercise: exercise, trackingMode: RepExerciseTrackingMode(rawValue: dto.trackingMode) ?? .repsWeight, weight: dto.weight, reps: dto.reps, holdSeconds: dto.holdSeconds)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: PersonalRecordDTO, to model: PersonalRecord, context: ModelContext) {
        model.trackingModeRaw = dto.trackingMode
        model.weight = dto.weight
        model.reps = dto.reps
        model.holdSeconds = dto.holdSeconds
        if model.exercise?.id != dto.exerciseId {
            model.exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}
