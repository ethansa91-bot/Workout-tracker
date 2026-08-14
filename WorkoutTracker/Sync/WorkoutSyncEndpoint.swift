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

struct WorkoutSectionDTO: Codable {
    let id: UUID
    /// nil for a template section (`WorkoutSection.workout == nil`) — not attached to
    /// any workout, so there's nothing to reference.
    let workoutId: UUID?
    let sortOrder: Int
    let sectionType: String
    let name: String?
    let description: String?
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(sectionType, forKey: .sectionType)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct TimeSectionStepDTO: Codable {
    let id: UUID
    let workoutSectionId: UUID
    let sortOrder: Int
    let stepType: String
    let exerciseId: UUID?
    let durationSeconds: Int
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutSectionId, forKey: .workoutSectionId)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(stepType, forKey: .stepType)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct RepSectionExerciseDTO: Codable {
    let id: UUID
    let workoutSectionId: UUID
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
        try c.encode(workoutSectionId, forKey: .workoutSectionId)
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
    let currentSectionIndex: Int
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
        try c.encode(currentSectionIndex, forKey: .currentSectionIndex)
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
    let timeSectionStepId: UUID?
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
        try c.encode(timeSectionStepId, forKey: .timeSectionStepId)
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
    let repSectionExerciseId: UUID?
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
        try c.encode(repSectionExerciseId, forKey: .repSectionExerciseId)
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

struct RecurringWorkoutScheduleDTO: Codable {
    let id: UUID
    let workoutId: UUID?
    let weekdays: [Int]
    let endDate: Date
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct ScheduledWorkoutDTO: Codable {
    let id: UUID
    let workoutId: UUID?
    let date: Date
    let recurringScheduleId: UUID?
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(date, forKey: .date)
        try c.encode(recurringScheduleId, forKey: .recurringScheduleId)
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

enum WorkoutSectionSyncAdapter: CatalogSyncAdapter {
    static let tableName = "workout_sections"
    static func dto(from model: WorkoutSection) -> WorkoutSectionDTO {
        WorkoutSectionDTO(id: model.id, workoutId: model.workout?.id, sortOrder: model.sortOrder, sectionType: model.sectionTypeRaw, name: model.name, description: model.sectionDescription, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: WorkoutSectionDTO) -> UUID { dto.id }
    static func updatedAt(of dto: WorkoutSectionDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: WorkoutSectionDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> WorkoutSection? {
        var descriptor = FetchDescriptor<WorkoutSection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: WorkoutSectionDTO, context: ModelContext) -> WorkoutSection {
        let workout = dto.workoutId.flatMap { WorkoutSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = WorkoutSection(id: dto.id, workout: workout, sortOrder: dto.sortOrder, sectionType: WorkoutSectionType(rawValue: dto.sectionType) ?? .time, name: dto.name, description: dto.description)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: WorkoutSectionDTO, to model: WorkoutSection, context: ModelContext) {
        model.sortOrder = dto.sortOrder
        model.sectionTypeRaw = dto.sectionType
        model.name = dto.name
        model.sectionDescription = dto.description
        if model.workout?.id != dto.workoutId {
            model.workout = dto.workoutId.flatMap { WorkoutSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}

enum TimeSectionStepSyncAdapter: CatalogSyncAdapter {
    static let tableName = "time_section_steps"
    static func dto(from model: TimeSectionStep) -> TimeSectionStepDTO {
        TimeSectionStepDTO(id: model.id, workoutSectionId: model.section?.id ?? UUID(), sortOrder: model.sortOrder, stepType: model.stepTypeRaw, exerciseId: model.exercise?.id, durationSeconds: model.durationSeconds, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: TimeSectionStepDTO) -> UUID { dto.id }
    static func updatedAt(of dto: TimeSectionStepDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: TimeSectionStepDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> TimeSectionStep? {
        var descriptor = FetchDescriptor<TimeSectionStep>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: TimeSectionStepDTO, context: ModelContext) -> TimeSectionStep {
        let section = WorkoutSectionSyncAdapter.fetchLocal(id: dto.workoutSectionId, context: context)
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = TimeSectionStep(id: dto.id, section: section, sortOrder: dto.sortOrder, stepType: TimeStepType(rawValue: dto.stepType) ?? .exercise, exercise: exercise, durationSeconds: dto.durationSeconds)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: TimeSectionStepDTO, to model: TimeSectionStep, context: ModelContext) {
        model.sortOrder = dto.sortOrder
        model.stepTypeRaw = dto.stepType
        model.durationSeconds = dto.durationSeconds
        if model.exercise?.id != dto.exerciseId {
            model.exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
        if model.section?.id != dto.workoutSectionId {
            model.section = WorkoutSectionSyncAdapter.fetchLocal(id: dto.workoutSectionId, context: context)
        }
    }
}

enum RepSectionExerciseSyncAdapter: CatalogSyncAdapter {
    static let tableName = "rep_section_exercises"
    static func dto(from model: RepSectionExercise) -> RepSectionExerciseDTO {
        RepSectionExerciseDTO(id: model.id, workoutSectionId: model.section?.id ?? UUID(), sortOrder: model.sortOrder, exerciseId: model.exercise?.id, targetSets: model.targetSets, customRestSeconds: model.customRestSeconds, trackingMode: model.trackingModeRaw, headStartSeconds: model.headStartSeconds, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: RepSectionExerciseDTO) -> UUID { dto.id }
    static func updatedAt(of dto: RepSectionExerciseDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: RepSectionExerciseDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> RepSectionExercise? {
        var descriptor = FetchDescriptor<RepSectionExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: RepSectionExerciseDTO, context: ModelContext) -> RepSectionExercise {
        let section = WorkoutSectionSyncAdapter.fetchLocal(id: dto.workoutSectionId, context: context)
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = RepSectionExercise(id: dto.id, section: section, sortOrder: dto.sortOrder, exercise: exercise, targetSets: dto.targetSets, customRestSeconds: dto.customRestSeconds, trackingMode: RepExerciseTrackingMode(rawValue: dto.trackingMode) ?? .repsWeight, headStartSeconds: dto.headStartSeconds)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: RepSectionExerciseDTO, to model: RepSectionExercise, context: ModelContext) {
        model.sortOrder = dto.sortOrder
        model.targetSets = dto.targetSets
        model.customRestSeconds = dto.customRestSeconds
        model.trackingModeRaw = dto.trackingMode
        model.headStartSeconds = dto.headStartSeconds
        if model.exercise?.id != dto.exerciseId {
            model.exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        }
        if model.section?.id != dto.workoutSectionId {
            model.section = WorkoutSectionSyncAdapter.fetchLocal(id: dto.workoutSectionId, context: context)
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
            currentSectionIndex: model.currentSectionIndex, currentStepIndex: model.currentStepIndex,
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
        model.currentSectionIndex = dto.currentSectionIndex
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
            id: model.id, sessionId: model.session?.id ?? UUID(), timeSectionStepId: model.timeSectionStep?.id,
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
        let step = dto.timeSectionStepId.flatMap { TimeSectionStepSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = StepLog(
            id: dto.id, session: session, timeSectionStep: step,
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
        if model.timeSectionStep?.id != dto.timeSectionStepId {
            model.timeSectionStep = dto.timeSectionStepId.flatMap { TimeSectionStepSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}

enum SetLogSyncAdapter: CatalogSyncAdapter {
    static let tableName = "set_logs"
    static func dto(from model: SetLog) -> SetLogDTO {
        SetLogDTO(
            id: model.id, sessionId: model.session?.id ?? UUID(), repSectionExerciseId: model.repSectionExercise?.id,
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
        let repEntry = dto.repSectionExerciseId.flatMap { RepSectionExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let exercise = dto.exerciseId.flatMap { ExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = SetLog(
            id: dto.id, session: session, repSectionExercise: repEntry, exercise: exercise,
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
        if model.repSectionExercise?.id != dto.repSectionExerciseId {
            model.repSectionExercise = dto.repSectionExerciseId.flatMap { RepSectionExerciseSyncAdapter.fetchLocal(id: $0, context: context) }
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

enum RecurringWorkoutScheduleSyncAdapter: CatalogSyncAdapter {
    static let tableName = "recurring_workout_schedules"
    static func dto(from model: RecurringWorkoutSchedule) -> RecurringWorkoutScheduleDTO {
        RecurringWorkoutScheduleDTO(id: model.id, workoutId: model.workout?.id, weekdays: model.weekdays, endDate: model.endDate, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: RecurringWorkoutScheduleDTO) -> UUID { dto.id }
    static func updatedAt(of dto: RecurringWorkoutScheduleDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: RecurringWorkoutScheduleDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> RecurringWorkoutSchedule? {
        var descriptor = FetchDescriptor<RecurringWorkoutSchedule>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: RecurringWorkoutScheduleDTO, context: ModelContext) -> RecurringWorkoutSchedule {
        let workout = dto.workoutId.flatMap { WorkoutSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = RecurringWorkoutSchedule(id: dto.id, workout: workout, weekdays: dto.weekdays, endDate: dto.endDate)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: RecurringWorkoutScheduleDTO, to model: RecurringWorkoutSchedule, context: ModelContext) {
        model.weekdays = dto.weekdays
        model.endDate = dto.endDate
        if model.workout?.id != dto.workoutId {
            model.workout = dto.workoutId.flatMap { WorkoutSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}

enum ScheduledWorkoutSyncAdapter: CatalogSyncAdapter {
    static let tableName = "scheduled_workouts"
    static func dto(from model: ScheduledWorkout) -> ScheduledWorkoutDTO {
        ScheduledWorkoutDTO(id: model.id, workoutId: model.workout?.id, date: model.date, recurringScheduleId: model.recurringSchedule?.id, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: ScheduledWorkoutDTO) -> UUID { dto.id }
    static func updatedAt(of dto: ScheduledWorkoutDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: ScheduledWorkoutDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> ScheduledWorkout? {
        var descriptor = FetchDescriptor<ScheduledWorkout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: ScheduledWorkoutDTO, context: ModelContext) -> ScheduledWorkout {
        let workout = dto.workoutId.flatMap { WorkoutSyncAdapter.fetchLocal(id: $0, context: context) }
        let schedule = dto.recurringScheduleId.flatMap { RecurringWorkoutScheduleSyncAdapter.fetchLocal(id: $0, context: context) }
        let model = ScheduledWorkout(id: dto.id, workout: workout, date: dto.date, recurringSchedule: schedule)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: ScheduledWorkoutDTO, to model: ScheduledWorkout, context: ModelContext) {
        model.date = dto.date
        if model.workout?.id != dto.workoutId {
            model.workout = dto.workoutId.flatMap { WorkoutSyncAdapter.fetchLocal(id: $0, context: context) }
        }
        if model.recurringSchedule?.id != dto.recurringScheduleId {
            model.recurringSchedule = dto.recurringScheduleId.flatMap { RecurringWorkoutScheduleSyncAdapter.fetchLocal(id: $0, context: context) }
        }
    }
}
