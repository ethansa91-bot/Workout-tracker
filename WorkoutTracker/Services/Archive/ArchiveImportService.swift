import Foundation
import SwiftData
import ZIPFoundation

/// Restores a `.zip` produced by `ArchiveExportService`.
///
/// Two policies decide everything here, and they resolve questions the rest of the
/// codebase leaves open:
///
/// **Validate before mutating.** Like `WorkoutImportService`, this saves as it goes, so
/// a failure partway through would strand half-restored data. Everything that can be
/// checked — format version, referential integrity, enum raw values — is checked against
/// the decoded payload first, and the import aborts before touching the context.
///
/// **Upsert by UUID, newest wins.** `WorkoutImportService` always inserts (re-running it
/// duplicates everything); `CatalogSeedLoader` skips existing rows and never updates
/// them. Neither is right for a backup: importing the same archive twice must be a no-op,
/// and importing onto a device that already has data must not clobber newer edits. So a
/// row is inserted when absent, and overwritten only when the archive's `updatedAt` is
/// strictly newer than what's on device.
@MainActor
enum ArchiveImportService {

    // MARK: - Reading

    /// Decodes and validates without mutating anything, so the UI can describe the
    /// archive in a confirmation prompt before the user commits.
    static func inspect(url: URL) throws -> ArchivePayload {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        // A file picked from Files/iCloud Drive is security-scoped; without this the
        // read fails with a bare permissions error.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: url, to: staging)
        } catch {
            throw ArchiveError.zipFailed(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest: ArchiveManifest = try decode(ArchiveFormat.manifestFile, in: staging, with: decoder, required: true)!
        guard manifest.formatVersion <= ArchiveFormat.currentVersion else {
            throw ArchiveError.unsupportedVersion(found: manifest.formatVersion, supported: ArchiveFormat.currentVersion)
        }

        let catalog: ArchiveCatalog = try decode(ArchiveFormat.catalogFile, in: staging, with: decoder, required: true)!
        let workouts: ArchiveWorkoutFile = try decode(ArchiveFormat.workoutsFile, in: staging, with: decoder, required: true)!
        let sessions: ArchiveSessionFile? = try decode(ArchiveFormat.sessionsFile, in: staging, with: decoder, required: false)

        // Image bytes are read into memory here rather than left on disk, because the
        // staging directory is torn down when this function returns.
        let images = readFiles(in: staging.appendingPathComponent(ArchiveFormat.imagesDirectory))
        let icons = readFiles(in: staging.appendingPathComponent(ArchiveFormat.iconsDirectory))

        let payload = ArchivePayload(
            manifest: manifest,
            catalog: catalog,
            workouts: workouts,
            sessions: sessions,
            images: images,
            icons: icons
        )
        try validate(payload)
        return payload
    }

    private static func decode<T: Decodable>(
        _ name: String, in staging: URL, with decoder: JSONDecoder, required: Bool
    ) throws -> T? {
        let url = staging.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else {
            if required { throw ArchiveError.missingFile(name) }
            return nil
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ArchiveError.corruptFile(name, underlying: error.localizedDescription)
        }
    }

    private static func readFiles(in directory: URL) -> [String: Data] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [:] }
        var result: [String: Data] = [:]
        for name in names {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name)) {
                result[name] = data
            }
        }
        return result
    }

    // MARK: - Validation

    /// Checks referential integrity across the whole payload before any row is touched.
    /// A dangling id here would otherwise surface as a silently-nil relationship halfway
    /// through the import, with earlier rows already saved.
    private static func validate(_ payload: ArchivePayload) throws {
        let exerciseIDs = Set(payload.catalog.exercises.map(\.id))
        let equipmentIDs = Set(payload.catalog.equipment.map(\.id))
        let muscleIDs = Set(payload.catalog.muscles.map(\.id))
        let muscleCategoryIDs = Set(payload.catalog.muscleCategories.map(\.id))
        let exerciseCategoryIDs = Set(payload.catalog.exerciseCategories.map(\.id))
        let workoutIDs = Set(payload.workouts.workouts.map(\.id))

        var problems: [String] = []
        func require(_ id: UUID?, in set: Set<UUID>, _ what: String) {
            guard let id, !set.contains(id) else { return }
            problems.append(what)
        }

        for muscle in payload.catalog.muscles {
            for categoryID in muscle.categoryIDs where !muscleCategoryIDs.contains(categoryID) {
                problems.append("muscle “\(muscle.name)” references a missing category")
            }
        }
        for combo in payload.catalog.weightCombos {
            require(combo.equipmentID, in: equipmentIDs, "a weight combo references missing equipment")
        }
        for exercise in payload.catalog.exercises {
            for id in exercise.equipmentIDs where !equipmentIDs.contains(id) {
                problems.append("exercise “\(exercise.name)” references missing equipment")
            }
            for id in exercise.muscleIDs where !muscleIDs.contains(id) {
                problems.append("exercise “\(exercise.name)” references a missing muscle")
            }
            for id in exercise.categoryIDs where !exerciseCategoryIDs.contains(id) {
                problems.append("exercise “\(exercise.name)” references a missing category")
            }
        }
        for record in payload.catalog.personalRecords {
            require(record.exerciseID, in: exerciseIDs, "a personal record references a missing exercise")
            require(record.equipmentID, in: equipmentIDs, "a personal record references missing equipment")
        }

        for section in payload.workouts.workouts.flatMap(\.sections) + payload.workouts.templates {
            let label = section.name ?? "untitled section"
            for step in section.timeSteps {
                require(step.exerciseID, in: exerciseIDs, "section “\(label)” references a missing exercise")
            }
            for rep in section.repExercises {
                require(rep.exerciseID, in: exerciseIDs, "section “\(label)” references a missing exercise")
                require(rep.preferredEquipmentID, in: equipmentIDs, "section “\(label)” references missing equipment")
            }
            for quick in section.quickExercises {
                require(quick.exerciseID, in: exerciseIDs, "section “\(label)” references a missing exercise")
            }
        }

        for schedule in payload.workouts.recurringSchedules {
            require(schedule.workoutID, in: workoutIDs, "a repeating schedule references a missing workout")
        }
        for scheduled in payload.workouts.scheduledWorkouts {
            require(scheduled.workoutID, in: workoutIDs, "a scheduled workout references a missing workout")
        }

        if let sessions = payload.sessions {
            let repExerciseIDs = Set(
                (payload.workouts.workouts.flatMap(\.sections) + payload.workouts.templates)
                    .flatMap(\.repExercises).map(\.id)
            )
            let timeStepIDs = Set(
                (payload.workouts.workouts.flatMap(\.sections) + payload.workouts.templates)
                    .flatMap(\.timeSteps).map(\.id)
            )
            for session in sessions.sessions {
                require(session.workoutID, in: workoutIDs, "a session references a missing workout")
                for log in session.setLogs {
                    require(log.exerciseID, in: exerciseIDs, "a logged set references a missing exercise")
                    require(log.equipmentID, in: equipmentIDs, "a logged set references missing equipment")
                    require(log.repSectionExerciseID, in: repExerciseIDs, "a logged set references a missing section exercise")
                }
                for log in session.stepLogs {
                    require(log.timeSectionStepID, in: timeStepIDs, "a logged step references a missing section step")
                }
                for note in session.exerciseNotes {
                    require(note.exerciseID, in: exerciseIDs, "a session note references a missing exercise")
                }
            }
        }

        guard problems.isEmpty else {
            let unique = Array(Set(problems)).sorted().prefix(5)
            var detail = unique.joined(separator: "\n• ")
            let extra = Set(problems).count - unique.count
            if extra > 0 { detail += "\n…and \(extra) more." }
            throw ArchiveError.corruptFile(
                "the archive",
                underlying: "it has broken internal references:\n• \(detail)"
            )
        }
    }

    // MARK: - Applying

    /// Order matters: catalog before workouts before sessions, so every id reference
    /// resolves against something already inserted.
    @discardableResult
    static func apply(_ payload: ArchivePayload, context: ModelContext) throws -> ArchiveImportSummary {
        var summary = ArchiveImportSummary()

        // Image bytes land before the Exercise rows that name them, so no
        // `generatedImageFileName` ever points at a file that isn't there yet.
        summary.imagesRestored = restoreImages(payload.images)
        summary.iconsRestored = restoreIcons(payload.icons)

        let muscleCategories = try upsertMuscleCategories(payload, context: context, summary: &summary)
        let exerciseCategories = try upsertExerciseCategories(payload, context: context, summary: &summary)
        let muscles = try upsertMuscles(payload, categories: muscleCategories, context: context, summary: &summary)
        let equipment = try upsertEquipment(payload, context: context, summary: &summary)
        try upsertWeightCombos(payload, equipment: equipment, context: context, summary: &summary)
        let exercises = try upsertExercises(
            payload, equipment: equipment, muscles: muscles,
            categories: exerciseCategories, context: context, summary: &summary
        )
        try upsertPersonalRecords(payload, exercises: exercises, equipment: equipment, context: context, summary: &summary)
        try upsertPersonalRecordEntries(payload, exercises: exercises, equipment: equipment, context: context, summary: &summary)

        let refs = WorkoutRefs(exercises: exercises, equipment: equipment)
        let workouts = try upsertWorkouts(payload, refs: refs, context: context, summary: &summary)
        try upsertSchedules(payload, workouts: workouts, context: context, summary: &summary)

        if let sessions = payload.sessions {
            try upsertSessions(sessions, payload: payload, workouts: workouts, refs: refs, context: context, summary: &summary)
        }

        try context.save()
        return summary
    }

    private struct WorkoutRefs {
        let exercises: [UUID: Exercise]
        let equipment: [UUID: Equipment]
    }

    /// One fetch per type, not one per row — the same reason `CatalogSeedLoader` builds
    /// id maps up front.
    private static func existingByID<T: PersistentModel>(
        _ type: T.Type, context: ModelContext, id: KeyPath<T, UUID>
    ) throws -> [UUID: T] {
        let rows = try context.fetch(FetchDescriptor<T>())
        return Dictionary(rows.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The newest-wins rule, in one place. Returns false when the on-device row is at
    /// least as new as the archive's, which is what makes a repeat import a no-op.
    private static func shouldOverwrite(existing: Date, incoming: Date) -> Bool {
        incoming > existing
    }

    // MARK: Catalog upserts

    private static func upsertMuscleCategories(
        _ payload: ArchivePayload, context: ModelContext, summary: inout ArchiveImportSummary
    ) throws -> [UUID: MuscleCategory] {
        var existing = try existingByID(MuscleCategory.self, context: context, id: \.id)
        for dto in payload.catalog.muscleCategories {
            if let row = existing[dto.id] {
                guard shouldOverwrite(existing: row.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("muscleCategories"); continue
                }
                row.name = dto.name
                row.updatedAt = dto.updatedAt
                row.deletedAt = dto.deletedAt
                summary.update("muscleCategories")
            } else {
                let row = MuscleCategory(id: dto.id, name: dto.name)
                row.updatedAt = dto.updatedAt
                row.deletedAt = dto.deletedAt
                context.insert(row)
                existing[dto.id] = row
                summary.insert("muscleCategories")
            }
        }
        return existing
    }

    private static func upsertExerciseCategories(
        _ payload: ArchivePayload, context: ModelContext, summary: inout ArchiveImportSummary
    ) throws -> [UUID: ExerciseCategory] {
        var existing = try existingByID(ExerciseCategory.self, context: context, id: \.id)
        for dto in payload.catalog.exerciseCategories {
            if let row = existing[dto.id] {
                guard shouldOverwrite(existing: row.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("exerciseCategories"); continue
                }
                row.name = dto.name
                row.updatedAt = dto.updatedAt
                row.deletedAt = dto.deletedAt
                summary.update("exerciseCategories")
            } else {
                let row = ExerciseCategory(id: dto.id, name: dto.name)
                row.updatedAt = dto.updatedAt
                row.deletedAt = dto.deletedAt
                context.insert(row)
                existing[dto.id] = row
                summary.insert("exerciseCategories")
            }
        }
        return existing
    }

    private static func upsertMuscles(
        _ payload: ArchivePayload, categories: [UUID: MuscleCategory],
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws -> [UUID: Muscle] {
        var existing = try existingByID(Muscle.self, context: context, id: \.id)
        for dto in payload.catalog.muscles {
            let resolved = dto.categoryIDs.compactMap { categories[$0] }
            if let row = existing[dto.id] {
                guard shouldOverwrite(existing: row.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("muscles"); continue
                }
                row.name = dto.name
                row.iconSymbolName = dto.iconSymbolName
                row.categories = resolved
                row.updatedAt = dto.updatedAt
                row.deletedAt = dto.deletedAt
                summary.update("muscles")
            } else {
                let row = Muscle(id: dto.id, name: dto.name, iconSymbolName: dto.iconSymbolName)
                row.categories = resolved
                row.updatedAt = dto.updatedAt
                row.deletedAt = dto.deletedAt
                context.insert(row)
                existing[dto.id] = row
                summary.insert("muscles")
            }
        }
        return existing
    }

    private static func upsertEquipment(
        _ payload: ArchivePayload, context: ModelContext, summary: inout ArchiveImportSummary
    ) throws -> [UUID: Equipment] {
        var existing = try existingByID(Equipment.self, context: context, id: \.id)
        for dto in payload.catalog.equipment {
            let row: Equipment
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("equipment"); continue
                }
                row = found
                summary.update("equipment")
            } else {
                row = Equipment(id: dto.id, name: dto.name, iconSymbolName: dto.iconSymbolName)
                context.insert(row)
                existing[dto.id] = row
                summary.insert("equipment")
            }
            row.name = dto.name
            row.iconSymbolName = dto.iconSymbolName
            row.isCustom = dto.isCustom
            // Assigned post-init: `Equipment.init` hardcodes this to false.
            row.isFavorited = dto.isFavorited
            row.isAtHome = dto.isAtHome
            row.isAtGym = dto.isAtGym
            row.isWeighted = dto.isWeighted
            row.preferredWeightUnit = dto.preferredWeightUnit
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }
        return existing
    }

    private static func upsertWeightCombos(
        _ payload: ArchivePayload, equipment: [UUID: Equipment],
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var existing = try existingByID(WeightCombo.self, context: context, id: \.id)
        for dto in payload.catalog.weightCombos {
            let row: WeightCombo
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("weightCombos"); continue
                }
                row = found
                summary.update("weightCombos")
            } else {
                row = WeightCombo(id: dto.id, value: dto.value, sortOrder: dto.sortOrder)
                context.insert(row)
                existing[dto.id] = row
                summary.insert("weightCombos")
            }
            row.equipment = dto.equipmentID.flatMap { equipment[$0] }
            row.value = dto.value
            row.sortOrder = dto.sortOrder
            row.label = dto.label
            row.colorRaw = dto.colorRaw
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }
    }

    private static func upsertExercises(
        _ payload: ArchivePayload, equipment: [UUID: Equipment], muscles: [UUID: Muscle],
        categories: [UUID: ExerciseCategory], context: ModelContext, summary: inout ArchiveImportSummary
    ) throws -> [UUID: Exercise] {
        var existing = try existingByID(Exercise.self, context: context, id: \.id)
        for dto in payload.catalog.exercises {
            let row: Exercise
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("exercises"); continue
                }
                row = found
                summary.update("exercises")
            } else {
                row = Exercise(id: dto.id, name: dto.name, iconSymbolName: dto.iconSymbolName)
                context.insert(row)
                existing[dto.id] = row
                summary.insert("exercises")
            }
            row.name = dto.name
            row.label = dto.label
            row.notes = dto.notes
            row.videoURL = dto.videoURL
            row.iconSymbolName = dto.iconSymbolName
            row.imageAssetName = dto.imageAssetName
            // Both assigned post-init — `Exercise.init` hardcodes them to nil.
            row.generatedImageFileName = dto.generatedImageFileName
            row.generatedImageStyle = dto.generatedImageStyle
            row.isCustom = dto.isCustom
            // Post-init too: the initializer forces `isFavorited || isCustom`, which
            // would silently favorite every custom exercise on restore.
            row.isFavorited = dto.isFavorited
            row.allowsBodyweight = dto.allowsBodyweight
            row.isOneSided = dto.isOneSided
            row.defaultEquipmentName = dto.defaultEquipmentName
            row.equipmentItems = dto.equipmentIDs.compactMap { equipment[$0] }
            row.muscles = dto.muscleIDs.compactMap { muscles[$0] }
            row.categories = dto.categoryIDs.compactMap { categories[$0] }
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }
        return existing
    }

    private static func upsertPersonalRecords(
        _ payload: ArchivePayload, exercises: [UUID: Exercise], equipment: [UUID: Equipment],
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var existing = try existingByID(PersonalRecord.self, context: context, id: \.id)
        for dto in payload.catalog.personalRecords {
            let row: PersonalRecord
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("personalRecords"); continue
                }
                row = found
                summary.update("personalRecords")
            } else {
                row = PersonalRecord(id: dto.id)
                context.insert(row)
                existing[dto.id] = row
                summary.insert("personalRecords")
            }
            row.exercise = dto.exerciseID.flatMap { exercises[$0] }
            row.equipment = dto.equipmentID.flatMap { equipment[$0] }
            row.weightUnit = dto.weightUnit
            row.isBodyweight = dto.isBodyweight
            row.trackingModeRaw = dto.trackingModeRaw
            row.weight = dto.weight
            row.reps = dto.reps
            row.holdSeconds = dto.holdSeconds
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }
    }

    /// Runs after `upsertPersonalRecords`, so every entry's parent record already exists
    /// to link to.
    private static func upsertPersonalRecordEntries(
        _ payload: ArchivePayload, exercises: [UUID: Exercise], equipment: [UUID: Equipment],
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        let records = try existingByID(PersonalRecord.self, context: context, id: \.id)
        var existing = try existingByID(PersonalRecordEntry.self, context: context, id: \.id)
        for dto in payload.catalog.personalRecordEntries {
            let row: PersonalRecordEntry
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("personalRecordEntries"); continue
                }
                row = found
                summary.update("personalRecordEntries")
            } else {
                row = PersonalRecordEntry(id: dto.id)
                context.insert(row)
                existing[dto.id] = row
                summary.insert("personalRecordEntries")
            }
            row.record = dto.recordID.flatMap { records[$0] }
            row.exercise = dto.exerciseID.flatMap { exercises[$0] }
            row.equipment = dto.equipmentID.flatMap { equipment[$0] }
            row.weightUnit = dto.weightUnit
            row.isBodyweight = dto.isBodyweight
            row.trackingModeRaw = dto.trackingModeRaw
            row.weight = dto.weight
            row.reps = dto.reps
            row.holdSeconds = dto.holdSeconds
            row.achievedAt = dto.achievedAt
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }
    }

    // MARK: Workout upserts

    private static func upsertWorkouts(
        _ payload: ArchivePayload, refs: WorkoutRefs,
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws -> [UUID: Workout] {
        var existing = try existingByID(Workout.self, context: context, id: \.id)
        var sections = try existingByID(WorkoutSection.self, context: context, id: \.id)

        for dto in payload.workouts.workouts {
            let workout: Workout
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("workouts"); continue
                }
                workout = found
                summary.update("workouts")
            } else {
                workout = Workout(id: dto.id, name: dto.name, notes: dto.notes, clonedFromWorkoutId: dto.clonedFromWorkoutId)
                context.insert(workout)
                existing[dto.id] = workout
                summary.insert("workouts")
            }
            workout.name = dto.name
            workout.notes = dto.notes
            workout.createdAt = dto.createdAt
            workout.clonedFromWorkoutId = dto.clonedFromWorkoutId
            workout.kindRaw = dto.kindRaw
            workout.isArchived = dto.isArchived
            workout.updatedAt = dto.updatedAt
            workout.deletedAt = dto.deletedAt

            for sectionDTO in dto.sections {
                try upsertSection(sectionDTO, workout: workout, into: &sections, refs: refs, context: context, summary: &summary)
            }
        }

        // A template is exactly a section with no parent workout.
        for templateDTO in payload.workouts.templates {
            try upsertSection(templateDTO, workout: nil, into: &sections, refs: refs, context: context, summary: &summary)
        }

        return existing
    }

    private static func upsertSection(
        _ dto: ArchiveSection, workout: Workout?, into sections: inout [UUID: WorkoutSection],
        refs: WorkoutRefs, context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        let section: WorkoutSection
        if let found = sections[dto.id] {
            guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                summary.skip("sections"); return
            }
            section = found
            summary.update("sections")
        } else {
            section = WorkoutSection(
                id: dto.id,
                sortOrder: dto.sortOrder,
                sectionType: WorkoutSectionType(rawValue: dto.sectionTypeRaw) ?? .time
            )
            context.insert(section)
            sections[dto.id] = section
            summary.insert("sections")
        }
        section.workout = workout
        section.sortOrder = dto.sortOrder
        section.name = dto.name
        section.sectionDescription = dto.sectionDescription
        section.sectionTypeRaw = dto.sectionTypeRaw
        section.emomRoundCount = dto.emomRoundCount
        section.amrapDurationSeconds = dto.amrapDurationSeconds
        section.autostart = dto.autostart
        section.repeatCount = dto.repeatCount
        section.updatedAt = dto.updatedAt
        section.deletedAt = dto.deletedAt

        try upsertTimeSteps(dto.timeSteps, section: section, refs: refs, context: context, summary: &summary)
        try upsertRepExercises(dto.repExercises, section: section, refs: refs, context: context, summary: &summary)
        try upsertQuickExercises(dto.quickExercises, section: section, refs: refs, context: context, summary: &summary)
    }

    private static func upsertTimeSteps(
        _ dtos: [ArchiveTimeStep], section: WorkoutSection, refs: WorkoutRefs,
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var existing = Dictionary(section.timeSteps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            let step: TimeSectionStep
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("timeSteps"); continue
                }
                step = found
                summary.update("timeSteps")
            } else {
                step = TimeSectionStep(
                    id: dto.id, section: section, sortOrder: dto.sortOrder,
                    stepType: TimeStepType(rawValue: dto.stepTypeRaw) ?? .exercise,
                    durationSeconds: dto.durationSeconds
                )
                context.insert(step)
                existing[dto.id] = step
                summary.insert("timeSteps")
            }
            step.section = section
            step.sortOrder = dto.sortOrder
            step.stepTypeRaw = dto.stepTypeRaw
            step.exercise = dto.exerciseID.flatMap { refs.exercises[$0] }
            step.durationSeconds = dto.durationSeconds
            step.colorRaw = dto.colorRaw
            step.updatedAt = dto.updatedAt
            step.deletedAt = dto.deletedAt
        }
    }

    private static func upsertRepExercises(
        _ dtos: [ArchiveRepExercise], section: WorkoutSection, refs: WorkoutRefs,
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var existing = Dictionary(section.repExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            let entry: RepSectionExercise
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("repExercises"); continue
                }
                entry = found
                summary.update("repExercises")
            } else {
                entry = RepSectionExercise(id: dto.id, section: section, sortOrder: dto.sortOrder, targetSets: dto.targetSets)
                context.insert(entry)
                existing[dto.id] = entry
                summary.insert("repExercises")
            }
            let exercise = dto.exerciseID.flatMap { refs.exercises[$0] }
            entry.section = section
            entry.sortOrder = dto.sortOrder
            entry.exercise = exercise
            entry.targetSets = dto.targetSets
            entry.customRestSeconds = dto.customRestSeconds
            entry.trackingModeRaw = dto.trackingModeRaw
            entry.headStartSeconds = dto.headStartSeconds
            // Same guards `WorkoutImportService` applies: a file can't switch on an
            // option the catalog exercise itself doesn't support.
            entry.allowsBodyweight = dto.allowsBodyweight && (exercise?.allowsBodyweight ?? false)
            entry.tracksSides = dto.tracksSides && (exercise?.isOneSided ?? false)
            if let equipmentID = dto.preferredEquipmentID,
               let equipment = refs.equipment[equipmentID],
               exercise?.equipmentItems.contains(where: { $0.id == equipment.id && $0.isWeighted }) == true {
                entry.preferredEquipment = equipment
            } else {
                entry.preferredEquipment = nil
            }
            entry.prefersBodyweight = dto.prefersBodyweight && (exercise?.allowsBodyweightSource ?? false)
            entry.updatedAt = dto.updatedAt
            entry.deletedAt = dto.deletedAt
        }
    }

    private static func upsertQuickExercises(
        _ dtos: [ArchiveQuickExercise], section: WorkoutSection, refs: WorkoutRefs,
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var existing = Dictionary(section.quickExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            let entry: SectionExerciseEntry
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("quickExercises"); continue
                }
                entry = found
                summary.update("quickExercises")
            } else {
                entry = SectionExerciseEntry(id: dto.id, section: section, sortOrder: dto.sortOrder)
                context.insert(entry)
                existing[dto.id] = entry
                summary.insert("quickExercises")
            }
            entry.section = section
            entry.sortOrder = dto.sortOrder
            entry.exercise = dto.exerciseID.flatMap { refs.exercises[$0] }
            entry.updatedAt = dto.updatedAt
            entry.deletedAt = dto.deletedAt
        }
    }

    private static func upsertSchedules(
        _ payload: ArchivePayload, workouts: [UUID: Workout],
        context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var recurring = try existingByID(RecurringWorkoutSchedule.self, context: context, id: \.id)
        for dto in payload.workouts.recurringSchedules {
            let row: RecurringWorkoutSchedule
            if let found = recurring[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("recurringSchedules"); continue
                }
                row = found
                summary.update("recurringSchedules")
            } else {
                row = RecurringWorkoutSchedule(
                    id: dto.id, workout: dto.workoutID.flatMap { workouts[$0] },
                    weekdays: dto.weekdays, endDate: dto.endDate
                )
                context.insert(row)
                recurring[dto.id] = row
                summary.insert("recurringSchedules")
            }
            row.workout = dto.workoutID.flatMap { workouts[$0] }
            row.weekdays = dto.weekdays
            row.endDate = dto.endDate
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }

        var scheduled = try existingByID(ScheduledWorkout.self, context: context, id: \.id)
        for dto in payload.workouts.scheduledWorkouts {
            let row: ScheduledWorkout
            if let found = scheduled[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("scheduledWorkouts"); continue
                }
                row = found
                summary.update("scheduledWorkouts")
            } else {
                row = ScheduledWorkout(id: dto.id, workout: dto.workoutID.flatMap { workouts[$0] }, date: dto.date)
                context.insert(row)
                scheduled[dto.id] = row
                summary.insert("scheduledWorkouts")
            }
            row.workout = dto.workoutID.flatMap { workouts[$0] }
            row.date = dto.date
            row.recurringSchedule = dto.recurringScheduleID.flatMap { recurring[$0] }
            row.updatedAt = dto.updatedAt
            row.deletedAt = dto.deletedAt
        }
    }

    // MARK: Session upserts

    private static func upsertSessions(
        _ file: ArchiveSessionFile, payload: ArchivePayload, workouts: [UUID: Workout],
        refs: WorkoutRefs, context: ModelContext, summary: inout ArchiveImportSummary
    ) throws {
        var existing = try existingByID(WorkoutSession.self, context: context, id: \.id)
        let repExercises = try existingByID(RepSectionExercise.self, context: context, id: \.id)
        let timeSteps = try existingByID(TimeSectionStep.self, context: context, id: \.id)

        for dto in file.sessions {
            let session: WorkoutSession
            if let found = existing[dto.id] {
                guard shouldOverwrite(existing: found.updatedAt, incoming: dto.updatedAt) else {
                    summary.skip("sessions"); continue
                }
                session = found
                summary.update("sessions")
            } else {
                session = WorkoutSession(id: dto.id, workout: dto.workoutID.flatMap { workouts[$0] })
                context.insert(session)
                existing[dto.id] = session
                summary.insert("sessions")
            }
            session.workout = dto.workoutID.flatMap { workouts[$0] }
            session.statusRaw = dto.statusRaw
            session.startedAt = dto.startedAt
            session.endedAt = dto.endedAt
            session.accumulatedActiveSeconds = dto.accumulatedActiveSeconds
            session.lastResumedAt = dto.lastResumedAt
            session.currentSectionIndex = dto.currentSectionIndex
            session.currentStepIndex = dto.currentStepIndex
            session.currentExerciseIndex = dto.currentExerciseIndex
            session.currentSetIndex = dto.currentSetIndex
            session.currentSectionRepeat = dto.currentSectionRepeat
            session.supersededBySessionId = dto.supersededBySessionId
            session.updatedAt = dto.updatedAt
            session.deletedAt = dto.deletedAt

            var setLogs = Dictionary(session.setLogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for logDTO in dto.setLogs {
                let log: SetLog
                if let found = setLogs[logDTO.id] {
                    guard shouldOverwrite(existing: found.updatedAt, incoming: logDTO.updatedAt) else {
                        summary.skip("setLogs"); continue
                    }
                    log = found
                    summary.update("setLogs")
                } else {
                    log = SetLog(
                        id: logDTO.id, session: session, setIndex: logDTO.setIndex,
                        reps: logDTO.reps, weight: logDTO.weight, weightUnit: logDTO.weightUnit
                    )
                    context.insert(log)
                    setLogs[logDTO.id] = log
                    summary.insert("setLogs")
                }
                log.session = session
                log.repSectionExercise = logDTO.repSectionExerciseID.flatMap { repExercises[$0] }
                log.exercise = logDTO.exerciseID.flatMap { refs.exercises[$0] }
                log.exerciseNameSnapshot = logDTO.exerciseNameSnapshot
                log.setIndex = logDTO.setIndex
                log.reps = logDTO.reps
                log.weight = logDTO.weight
                log.weightUnit = logDTO.weightUnit
                log.holdSeconds = logDTO.holdSeconds
                log.isBodyweight = logDTO.isBodyweight
                log.sideRaw = logDTO.sideRaw
                log.repeatIndex = logDTO.repeatIndex
                log.equipment = logDTO.equipmentID.flatMap { refs.equipment[$0] }
                log.isManualWeight = logDTO.isManualWeight
                log.loggedAt = logDTO.loggedAt
                log.isCancelled = logDTO.isCancelled
                log.updatedAt = logDTO.updatedAt
                log.deletedAt = logDTO.deletedAt
            }

            var stepLogs = Dictionary(session.stepLogs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for logDTO in dto.stepLogs {
                let log: StepLog
                if let found = stepLogs[logDTO.id] {
                    guard shouldOverwrite(existing: found.updatedAt, incoming: logDTO.updatedAt) else {
                        summary.skip("stepLogs"); continue
                    }
                    log = found
                    summary.update("stepLogs")
                } else {
                    log = StepLog(
                        id: logDTO.id, session: session,
                        plannedDurationSeconds: logDTO.plannedDurationSeconds,
                        actualDurationSeconds: logDTO.actualDurationSeconds,
                        outcome: StepOutcome(rawValue: logDTO.outcomeRaw) ?? .completed,
                        sortOrder: logDTO.sortOrder
                    )
                    context.insert(log)
                    stepLogs[logDTO.id] = log
                    summary.insert("stepLogs")
                }
                log.session = session
                log.timeSectionStep = logDTO.timeSectionStepID.flatMap { timeSteps[$0] }
                log.stepExerciseNameSnapshot = logDTO.stepExerciseNameSnapshot
                log.plannedDurationSeconds = logDTO.plannedDurationSeconds
                log.actualDurationSeconds = logDTO.actualDurationSeconds
                log.outcomeRaw = logDTO.outcomeRaw
                log.loggedAt = logDTO.loggedAt
                log.sortOrder = logDTO.sortOrder
                log.repeatIndex = logDTO.repeatIndex
                log.updatedAt = logDTO.updatedAt
                log.deletedAt = logDTO.deletedAt
            }

            // Notes are keyed by (session, exercise) rather than by id, matching the
            // one-note-per-pair invariant `findOrCreate` enforces — restoring by id
            // alone could produce a second note for a pair that already has one.
            var notesByExercise: [UUID: ExerciseSessionNote] = [:]
            for note in session.exerciseNotes {
                if let exerciseID = note.exercise?.id { notesByExercise[exerciseID] = note }
            }
            for noteDTO in dto.exerciseNotes {
                guard let exerciseID = noteDTO.exerciseID, let exercise = refs.exercises[exerciseID] else {
                    summary.skip("exerciseNotes"); continue
                }
                if let found = notesByExercise[exerciseID] {
                    guard shouldOverwrite(existing: found.updatedAt, incoming: noteDTO.updatedAt) else {
                        summary.skip("exerciseNotes"); continue
                    }
                    found.text = noteDTO.text
                    found.updatedAt = noteDTO.updatedAt
                    summary.update("exerciseNotes")
                } else {
                    let note = ExerciseSessionNote(id: noteDTO.id, session: session, exercise: exercise, text: noteDTO.text)
                    note.exerciseNameSnapshot = noteDTO.exerciseNameSnapshot
                    note.createdAt = noteDTO.createdAt
                    note.updatedAt = noteDTO.updatedAt
                    context.insert(note)
                    notesByExercise[exerciseID] = note
                    summary.insert("exerciseNotes")
                }
            }
        }
    }

    // MARK: Image restore

    private static func restoreImages(_ images: [String: Data]) -> Int {
        var count = 0
        for (fileName, data) in images {
            do {
                try GeneratedExerciseImageStore.restore(data, fileName: fileName)
                count += 1
            } catch {
                continue
            }
        }
        return count
    }

    private static func restoreIcons(_ icons: [String: Data]) -> Int {
        guard let directory = BundleThenDiskIconProvider().onDiskIconDirectory() else { return 0 }
        var count = 0
        for (fileName, data) in icons {
            guard (try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)) != nil else { continue }
            count += 1
        }
        return count
    }
}

/// A decoded, validated archive, held in memory between "inspect" and "apply" so the UI
/// can describe it before the user commits to importing.
struct ArchivePayload {
    let manifest: ArchiveManifest
    let catalog: ArchiveCatalog
    let workouts: ArchiveWorkoutFile
    let sessions: ArchiveSessionFile?
    let images: [String: Data]
    let icons: [String: Data]
}
