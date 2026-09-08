import Foundation
import SwiftData
import ZIPFoundation

/// Writes every piece of user data — catalog, workouts, templates, schedules, optional
/// session history, and the image bytes that CloudKit can't carry — into a single `.zip`.
///
/// Tombstones (`deletedAt != nil`) are included deliberately: a restore should reproduce
/// what the user deleted, not resurrect it.
@MainActor
enum ArchiveExportService {

    /// Builds the archive in a temp directory and returns the `.zip` URL. The caller
    /// owns the file and should hand it to `fileExporter`; the staging directory is
    /// cleaned up before returning either way.
    static func makeArchive(context: ModelContext, includeSessionHistory: Bool) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        let staging = root.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let encoder = JSONEncoder()
        // Matches the existing exporter's formatting so archives diff cleanly.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let catalog = try buildCatalog(context: context)
        let workoutFile = try buildWorkouts(context: context)
        let sessionFile = includeSessionHistory ? try buildSessions(context: context) : nil

        try encoder.encode(catalog).write(to: staging.appendingPathComponent(ArchiveFormat.catalogFile))
        try encoder.encode(workoutFile).write(to: staging.appendingPathComponent(ArchiveFormat.workoutsFile))
        if let sessionFile {
            try encoder.encode(sessionFile).write(to: staging.appendingPathComponent(ArchiveFormat.sessionsFile))
        }

        let imageCount = try copyGeneratedImages(catalog: catalog, into: staging)
        let iconCount = try copyIcons(into: staging)

        var counts: [String: Int] = [
            "exercises": catalog.exercises.count,
            "equipment": catalog.equipment.count,
            "executionTypes": catalog.executionTypes.count,
            "muscles": catalog.muscles.count,
            "personalRecords": catalog.personalRecords.count,
            "workouts": workoutFile.workouts.count,
            "templates": workoutFile.templates.count,
            "images": imageCount,
            "icons": iconCount
        ]
        if let sessionFile {
            counts["sessions"] = sessionFile.sessions.count
            counts["sectionResults"] = sessionFile.sessions.reduce(0) { $0 + $1.sectionResultLogs.count }
        }

        let manifest = ArchiveManifest(
            formatVersion: ArchiveFormat.currentVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            exportedAt: .now,
            includesSessionHistory: includeSessionHistory,
            counts: counts
        )
        try encoder.encode(manifest).write(to: staging.appendingPathComponent(ArchiveFormat.manifestFile))

        let zipURL = root.appendingPathComponent(defaultFilename() + ".zip")
        do {
            // shouldKeepParent: false — entries sit at the archive root, not nested
            // under a "payload/" folder.
            try fileManager.zipItem(at: staging, to: zipURL, shouldKeepParent: false)
        } catch {
            throw ArchiveError.zipFailed(error.localizedDescription)
        }
        return zipURL
    }

    static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "workout-archive-\(formatter.string(from: Date()))"
    }

    /// Counts for the pre-export summary, without building anything.
    static func previewCounts(context: ModelContext) -> (exercises: Int, workouts: Int, sessions: Int, images: Int) {
        let exercises = (try? context.fetchCount(FetchDescriptor<Exercise>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        let workouts = (try? context.fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        let sessions = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        let images = GeneratedExerciseImageStore.allFileNames().count
        return (exercises, workouts, sessions, images)
    }

    // MARK: - Catalog

    private static func buildCatalog(context: ModelContext) throws -> ArchiveCatalog {
        var catalog = ArchiveCatalog()

        catalog.muscleCategories = try context.fetch(FetchDescriptor<MuscleCategory>()).map {
            ArchiveMuscleCategory(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt)
        }
        catalog.muscles = try context.fetch(FetchDescriptor<Muscle>()).map {
            ArchiveMuscle(
                id: $0.id,
                name: $0.name,
                iconSymbolName: $0.iconSymbolName,
                categoryIDs: $0.categories.map(\.id),
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.exerciseCategories = try context.fetch(FetchDescriptor<ExerciseCategory>()).map {
            ArchiveExerciseCategory(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt)
        }
        catalog.equipment = try context.fetch(FetchDescriptor<Equipment>()).map {
            ArchiveEquipment(
                id: $0.id,
                name: $0.name,
                iconSymbolName: $0.iconSymbolName,
                isCustom: $0.isCustom,
                isFavorited: $0.isFavorited,
                isAtHome: $0.isAtHome,
                isAtGym: $0.isAtGym,
                isWeighted: $0.isWeighted,
                preferredWeightUnit: $0.preferredWeightUnit,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.executionTypes = try context.fetch(FetchDescriptor<ExecutionType>()).map {
            ArchiveExecutionType(
                id: $0.id,
                name: $0.name,
                isCustom: $0.isCustom,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.workoutTags = try context.fetch(FetchDescriptor<WorkoutTag>()).map {
            ArchiveWorkoutTag(
                id: $0.id,
                name: $0.name,
                isCustom: $0.isCustom,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.progressionGroups = try context.fetch(FetchDescriptor<ProgressionGroup>()).map {
            ArchiveProgressionGroup(
                id: $0.id,
                reachedLevel: $0.reachedLevel,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.progressionSteps = try context.fetch(FetchDescriptor<ProgressionStep>()).map {
            ArchiveProgressionStep(
                id: $0.id,
                groupID: $0.group?.id,
                exerciseID: $0.exercise?.id,
                level: $0.level,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.weightCombos = try context.fetch(FetchDescriptor<WeightCombo>()).map {
            ArchiveWeightCombo(
                id: $0.id,
                equipmentID: $0.equipment?.id,
                value: $0.value,
                sortOrder: $0.sortOrder,
                label: $0.label,
                colorRaw: $0.colorRaw,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.exercises = try context.fetch(FetchDescriptor<Exercise>()).map {
            ArchiveExercise(
                id: $0.id,
                name: $0.name,
                label: $0.label,
                notes: $0.notes,
                videoURL: $0.videoURL,
                iconSymbolName: $0.iconSymbolName,
                imageAssetName: $0.imageAssetName,
                generatedImageFileName: $0.generatedImageFileName,
                generatedImageStyle: $0.generatedImageStyle,
                isCustom: $0.isCustom,
                isFavorited: $0.isFavorited,
                allowsBodyweight: $0.allowsBodyweight,
                isOneSided: $0.isOneSided,
                defaultEquipmentName: $0.defaultEquipmentName,
                defaultsToBodyweight: $0.defaultsToBodyweight,
                equipmentIDs: $0.equipmentItems.map(\.id),
                executionTypeIDs: $0.executionTypes.map(\.id),
                separateRecordsPerExecutionType: $0.separateRecordsPerExecutionType,
                muscleIDs: $0.muscles.map(\.id),
                categoryIDs: $0.categories.map(\.id),
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.personalRecords = try context.fetch(FetchDescriptor<PersonalRecord>()).map {
            ArchivePersonalRecord(
                id: $0.id,
                exerciseID: $0.exercise?.id,
                equipmentID: $0.equipment?.id,
                executionTypeID: $0.executionType?.id,
                weightUnit: $0.weightUnit,
                isBodyweight: $0.isBodyweight,
                isFollowAlong: $0.isFollowAlong,
                trackingModeRaw: $0.trackingModeRaw,
                weight: $0.weight,
                reps: $0.reps,
                holdSeconds: $0.holdSeconds,
                sectionRecordGroupID: $0.sectionRecordGroupID,
                sectionRecordKindRaw: $0.sectionRecordKindRaw,
                sectionRecordName: $0.sectionRecordName,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        catalog.personalRecordEntries = try context.fetch(FetchDescriptor<PersonalRecordEntry>()).map {
            ArchivePersonalRecordEntry(
                id: $0.id,
                recordID: $0.record?.id,
                exerciseID: $0.exercise?.id,
                equipmentID: $0.equipment?.id,
                executionTypeID: $0.executionType?.id,
                weightUnit: $0.weightUnit,
                isBodyweight: $0.isBodyweight,
                isFollowAlong: $0.isFollowAlong,
                trackingModeRaw: $0.trackingModeRaw,
                weight: $0.weight,
                reps: $0.reps,
                holdSeconds: $0.holdSeconds,
                sectionRecordGroupID: $0.sectionRecordGroupID,
                sectionRecordKindRaw: $0.sectionRecordKindRaw,
                sectionRecordName: $0.sectionRecordName,
                achievedAt: $0.achievedAt,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        return catalog
    }

    // MARK: - Workouts

    private static func buildWorkouts(context: ModelContext) throws -> ArchiveWorkoutFile {
        var file = ArchiveWorkoutFile()

        file.workouts = try context.fetch(FetchDescriptor<Workout>()).map(workoutOut)

        // Templates have no parent workout, so they can't ride along inside `workouts`.
        file.templates = try context.fetch(FetchDescriptor<WorkoutSection>())
            .filter { $0.isTemplate }
            .map(sectionOut)

        file.recurringSchedules = try context.fetch(FetchDescriptor<RecurringWorkoutSchedule>()).map {
            ArchiveRecurringSchedule(
                id: $0.id,
                workoutID: $0.workout?.id,
                weekdays: $0.weekdays,
                endDate: $0.endDate,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        file.scheduledWorkouts = try context.fetch(FetchDescriptor<ScheduledWorkout>()).map {
            ArchiveScheduledWorkout(
                id: $0.id,
                workoutID: $0.workout?.id,
                date: $0.date,
                recurringScheduleID: $0.recurringSchedule?.id,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt
            )
        }
        return file
    }

    /// One workout to its DTO. Internal rather than private because sharing publishes a
    /// single workout through the same mapping — the wire format is identical, only the
    /// transport differs.
    ///
    /// Note this keeps tombstoned sections: an archive is a backup and must round-trip
    /// deletions. Callers that want only live rows (sharing does) filter on `deletedAt`.
    static func workoutOut(_ workout: Workout) -> ArchiveWorkout {
        ArchiveWorkout(
            id: workout.id,
            name: workout.name,
            notes: workout.notes,
            createdAt: workout.createdAt,
            clonedFromWorkoutId: workout.clonedFromWorkoutId,
            kindRaw: workout.kindRaw,
            isArchived: workout.isArchived,
            tagIDs: workout.tags.map(\.id),
            sections: workout.sections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(sectionOut),
            versionGroupID: workout.versionGroupID,
            isSupersededVersion: workout.isSupersededVersion,
            updatedAt: workout.updatedAt,
            deletedAt: workout.deletedAt
        )
    }

    static func sectionOut(_ section: WorkoutSection) -> ArchiveSection {
        ArchiveSection(
            id: section.id,
            sortOrder: section.sortOrder,
            name: section.name,
            sectionDescription: section.sectionDescription,
            sectionTypeRaw: section.sectionTypeRaw,
            emomRoundCount: section.emomRoundCount,
            amrapDurationSeconds: section.amrapDurationSeconds,
            autostart: section.autostart,
            repeatCount: section.repeatCount,
            getReadySeconds: section.getReadySeconds,
            repeatsGetReadyEachPass: section.repeatsGetReadyEachPass,
            sectionRestSeconds: section.sectionRestSeconds,
            emomToFailure: section.emomToFailure,
            tracksRecord: section.tracksRecord,
            recordGroupID: section.recordGroupID,
            recordLockedAt: section.recordLockedAt,
            tagIDs: section.tags.map(\.id),
            timeSteps: section.timeSteps
                .sorted { $0.sortOrder < $1.sortOrder }
                .map {
                    ArchiveTimeStep(
                        id: $0.id,
                        sortOrder: $0.sortOrder,
                        stepTypeRaw: $0.stepTypeRaw,
                        exerciseID: $0.exercise?.id,
                        durationSeconds: $0.durationSeconds,
                        colorRaw: $0.colorRaw,
                        executionTypeID: $0.executionType?.id,
                        sideRaw: $0.sideRaw,
                        preferredEquipmentID: $0.preferredEquipment?.id,
                        prefersBodyweight: $0.prefersBodyweight,
                        startingWeight: $0.startingWeight,
                        updatedAt: $0.updatedAt,
                        deletedAt: $0.deletedAt
                    )
                },
            repExercises: section.repExercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map {
                    ArchiveRepExercise(
                        id: $0.id,
                        sortOrder: $0.sortOrder,
                        exerciseID: $0.exercise?.id,
                        targetSets: $0.targetSets,
                        customRestSeconds: $0.customRestSeconds,
                        trackingModeRaw: $0.trackingModeRaw,
                        headStartSeconds: $0.headStartSeconds,
                        allowsBodyweight: $0.allowsBodyweight,
                        tracksSides: $0.tracksSides,
                        preferredEquipmentID: $0.preferredEquipment?.id,
                        prefersBodyweight: $0.prefersBodyweight,
                        executionTypeID: $0.executionType?.id,
                        progressionEnabled: $0.progressionEnabled,
                        startingWeight: $0.startingWeight,
                        startingReps: $0.startingReps,
                        updatedAt: $0.updatedAt,
                        deletedAt: $0.deletedAt
                    )
                },
            quickExercises: section.quickExercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map {
                    ArchiveQuickExercise(
                        id: $0.id,
                        sortOrder: $0.sortOrder,
                        exerciseID: $0.exercise?.id,
                        executionTypeID: $0.executionType?.id,
                        targetReps: $0.targetReps,
                        sideRaw: $0.sideRaw,
                        updatedAt: $0.updatedAt,
                        deletedAt: $0.deletedAt
                    )
                },
            updatedAt: section.updatedAt,
            deletedAt: section.deletedAt
        )
    }

    // MARK: - Sessions

    private static func buildSessions(context: ModelContext) throws -> ArchiveSessionFile {
        var file = ArchiveSessionFile()
        file.sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).map { session in
            ArchiveSession(
                id: session.id,
                workoutID: session.workout?.id,
                statusRaw: session.statusRaw,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                accumulatedActiveSeconds: session.accumulatedActiveSeconds,
                lastResumedAt: session.lastResumedAt,
                currentSectionIndex: session.currentSectionIndex,
                currentStepIndex: session.currentStepIndex,
                currentExerciseIndex: session.currentExerciseIndex,
                currentSetIndex: session.currentSetIndex,
                currentSectionRepeat: session.currentSectionRepeat,
                isSectionResting: session.isSectionResting,
                supersededBySessionId: session.supersededBySessionId,
                setLogs: session.setLogs.map {
                    ArchiveSetLog(
                        id: $0.id,
                        repSectionExerciseID: $0.repSectionExercise?.id,
                        exerciseID: $0.exercise?.id,
                        exerciseNameSnapshot: $0.exerciseNameSnapshot,
                        setIndex: $0.setIndex,
                        reps: $0.reps,
                        weight: $0.weight,
                        weightUnit: $0.weightUnit,
                        holdSeconds: $0.holdSeconds,
                        isBodyweight: $0.isBodyweight,
                        sideRaw: $0.sideRaw,
                        repeatIndex: $0.repeatIndex,
                        equipmentID: $0.equipment?.id,
                        isManualWeight: $0.isManualWeight,
                        executionTypeID: $0.executionType?.id,
                        loggedAt: $0.loggedAt,
                        isCancelled: $0.isCancelled,
                        updatedAt: $0.updatedAt,
                        deletedAt: $0.deletedAt
                    )
                },
                stepLogs: session.stepLogs.map {
                    ArchiveStepLog(
                        id: $0.id,
                        timeSectionStepID: $0.timeSectionStep?.id,
                        stepExerciseNameSnapshot: $0.stepExerciseNameSnapshot,
                        executionTypeID: $0.executionType?.id,
                        plannedDurationSeconds: $0.plannedDurationSeconds,
                        actualDurationSeconds: $0.actualDurationSeconds,
                        outcomeRaw: $0.outcomeRaw,
                        loggedAt: $0.loggedAt,
                        sortOrder: $0.sortOrder,
                        repeatIndex: $0.repeatIndex,
                        updatedAt: $0.updatedAt,
                        deletedAt: $0.deletedAt
                    )
                },
                sectionResultLogs: session.sectionResultLogs.map {
                    ArchiveSectionResultLog(
                        id: $0.id,
                        sectionID: $0.section?.id,
                        recordGroupID: $0.recordGroupID,
                        sectionNameSnapshot: $0.sectionNameSnapshot,
                        sectionTypeRaw: $0.sectionTypeRaw,
                        repeatIndex: $0.repeatIndex,
                        value: $0.value,
                        loggedAt: $0.loggedAt,
                        updatedAt: $0.updatedAt,
                        deletedAt: $0.deletedAt
                    )
                },
                exerciseNotes: session.exerciseNotes.map {
                    ArchiveExerciseNote(
                        id: $0.id,
                        exerciseID: $0.exercise?.id,
                        exerciseNameSnapshot: $0.exerciseNameSnapshot,
                        text: $0.text,
                        createdAt: $0.createdAt,
                        updatedAt: $0.updatedAt
                    )
                },
                updatedAt: session.updatedAt,
                deletedAt: session.deletedAt
            )
        }
        return file
    }

    // MARK: - Image bytes

    /// Only images an exercise actually points at — orphans left behind by a since-deleted
    /// exercise would bloat the archive for nothing.
    private static func copyGeneratedImages(catalog: ArchiveCatalog, into staging: URL) throws -> Int {
        let referenced = Set(catalog.exercises.compactMap(\.generatedImageFileName))
        guard !referenced.isEmpty else { return 0 }

        let directory = staging.appendingPathComponent(ArchiveFormat.imagesDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var count = 0
        for fileName in referenced {
            guard let data = GeneratedExerciseImageStore.data(fileName: fileName) else { continue }
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            count += 1
        }
        return count
    }

    private static func copyIcons(into staging: URL) throws -> Int {
        let fileManager = FileManager.default
        guard let source = BundleThenDiskIconProvider().onDiskIconDirectory(),
              let names = try? fileManager.contentsOfDirectory(atPath: source.path),
              !names.isEmpty
        else { return 0 }

        let directory = staging.appendingPathComponent(ArchiveFormat.iconsDirectory, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var count = 0
        for name in names {
            guard let data = try? Data(contentsOf: source.appendingPathComponent(name)) else { continue }
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            count += 1
        }
        return count
    }
}
