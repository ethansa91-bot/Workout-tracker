import Foundation

/// Wire format for the full-data archive: every model, by UUID, with timestamps.
///
/// Unlike `WorkoutExportService`/`WorkoutImportService` — which keep deliberately
/// separate Encodable/Decodable halves so a lenient reader can absorb hand-written seed
/// files — these DTOs are shared by both sides on purpose. This format is only ever
/// machine-written and machine-read, and one shared type is what guarantees a field
/// added to the writer can't be silently forgotten by the reader.
///
/// Two rules the seed format doesn't follow, both load-bearing:
/// - **Real UUIDs, never names.** Relationships are id references, so renaming an
///   exercise can't break a workout that points at it (the seed format's
///   name-resolution is exactly why `WorkoutExportService` must write `name` and never
///   `displayName`).
/// - **Tombstones travel.** Rows with `deletedAt` set are exported too, so a restore
///   reproduces deletions instead of resurrecting what the user removed.
enum ArchiveFormat {
    /// Bumped only for breaking changes. The importer refuses anything higher.
    static let currentVersion = 1

    static let manifestFile = "manifest.json"
    static let catalogFile = "catalog.json"
    static let workoutsFile = "workouts.json"
    static let sessionsFile = "sessions.json"
    static let imagesDirectory = "images"
    static let iconsDirectory = "icons"
}

// MARK: - Manifest

struct ArchiveManifest: Codable {
    var formatVersion: Int
    var appVersion: String?
    var exportedAt: Date
    var includesSessionHistory: Bool
    var counts: [String: Int]
}

// MARK: - Catalog

struct ArchiveCatalog: Codable {
    var muscleCategories: [ArchiveMuscleCategory] = []
    var muscles: [ArchiveMuscle] = []
    var exerciseCategories: [ArchiveExerciseCategory] = []
    var equipment: [ArchiveEquipment] = []
    var weightCombos: [ArchiveWeightCombo] = []
    var exercises: [ArchiveExercise] = []
    var personalRecords: [ArchivePersonalRecord] = []
    /// Defaulted so archives written before record history existed still decode.
    var personalRecordEntries: [ArchivePersonalRecordEntry] = []
}

struct ArchiveMuscleCategory: Codable {
    var id: UUID
    var name: String
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveMuscle: Codable {
    var id: UUID
    var name: String
    var iconSymbolName: String
    var categoryIDs: [UUID]
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveExerciseCategory: Codable {
    var id: UUID
    var name: String
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveEquipment: Codable {
    var id: UUID
    var name: String
    var iconSymbolName: String
    var isCustom: Bool
    /// Deprecated in the app, still stored — carried so a restore is byte-faithful.
    var isFavorited: Bool
    var isAtHome: Bool
    var isAtGym: Bool
    var isWeighted: Bool
    var preferredWeightUnit: String?
    var updatedAt: Date
    var deletedAt: Date?
}

/// Flat, not nested under equipment: `label` and `colorRaw` make these real rows with
/// their own identity, which the seed format's bare `weights: [Double]` can't express.
struct ArchiveWeightCombo: Codable {
    var id: UUID
    var equipmentID: UUID?
    var value: Double
    var sortOrder: Int
    var label: String?
    var colorRaw: String?
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveExercise: Codable {
    var id: UUID
    var name: String
    var label: String?
    var notes: String?
    var videoURL: String?
    var iconSymbolName: String
    /// Asset-catalog name — a reference into the compiled app bundle, so the archive
    /// carries the name and never the pixels.
    var imageAssetName: String?
    /// Filename under `images/` in the archive. The bytes ship alongside; these are the
    /// only exercise images that exist solely on-device and can't reach another device
    /// any other way.
    var generatedImageFileName: String?
    var generatedImageStyle: String?
    var isCustom: Bool
    var isFavorited: Bool
    var allowsBodyweight: Bool
    var isOneSided: Bool
    var defaultEquipmentName: String?
    var equipmentIDs: [UUID]
    var muscleIDs: [UUID]
    var categoryIDs: [UUID]
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchivePersonalRecord: Codable {
    var id: UUID
    var exerciseID: UUID?
    var equipmentID: UUID?
    var weightUnit: String?
    var isBodyweight: Bool
    var trackingModeRaw: String
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchivePersonalRecordEntry: Codable {
    var id: UUID
    var recordID: UUID?
    var exerciseID: UUID?
    var equipmentID: UUID?
    var weightUnit: String?
    var isBodyweight: Bool
    var trackingModeRaw: String
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    var achievedAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

// MARK: - Workouts

struct ArchiveWorkoutFile: Codable {
    var workouts: [ArchiveWorkout] = []
    /// Standalone template sections — they have no parent workout, so they have nowhere
    /// to live under `workouts`.
    var templates: [ArchiveSection] = []
    var recurringSchedules: [ArchiveRecurringSchedule] = []
    var scheduledWorkouts: [ArchiveScheduledWorkout] = []
}

struct ArchiveWorkout: Codable {
    var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var clonedFromWorkoutId: UUID?
    var kindRaw: String
    var isArchived: Bool
    var sections: [ArchiveSection]
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveSection: Codable {
    var id: UUID
    var sortOrder: Int
    var name: String?
    var sectionDescription: String?
    var sectionTypeRaw: String
    var emomRoundCount: Int
    var amrapDurationSeconds: Int
    var autostart: Bool
    var repeatCount: Int
    var timeSteps: [ArchiveTimeStep]
    var repExercises: [ArchiveRepExercise]
    var quickExercises: [ArchiveQuickExercise]
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveTimeStep: Codable {
    var id: UUID
    var sortOrder: Int
    var stepTypeRaw: String
    var exerciseID: UUID?
    var durationSeconds: Int
    var colorRaw: String?
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveRepExercise: Codable {
    var id: UUID
    var sortOrder: Int
    var exerciseID: UUID?
    var targetSets: Int
    var customRestSeconds: Int?
    var trackingModeRaw: String
    var headStartSeconds: Int
    var allowsBodyweight: Bool
    var tracksSides: Bool
    var preferredEquipmentID: UUID?
    var prefersBodyweight: Bool
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveQuickExercise: Codable {
    var id: UUID
    var sortOrder: Int
    var exerciseID: UUID?
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveRecurringSchedule: Codable {
    var id: UUID
    var workoutID: UUID?
    var weekdays: [Int]
    var endDate: Date
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveScheduledWorkout: Codable {
    var id: UUID
    var workoutID: UUID?
    var date: Date
    var recurringScheduleID: UUID?
    var updatedAt: Date
    var deletedAt: Date?
}

// MARK: - Sessions

struct ArchiveSessionFile: Codable {
    var sessions: [ArchiveSession] = []
}

struct ArchiveSession: Codable {
    var id: UUID
    var workoutID: UUID?
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date?
    var accumulatedActiveSeconds: Double
    var lastResumedAt: Date?
    var currentSectionIndex: Int
    var currentStepIndex: Int?
    var currentExerciseIndex: Int?
    var currentSetIndex: Int?
    var currentSectionRepeat: Int?
    var supersededBySessionId: UUID?
    var setLogs: [ArchiveSetLog]
    var stepLogs: [ArchiveStepLog]
    var exerciseNotes: [ArchiveExerciseNote]
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveSetLog: Codable {
    var id: UUID
    var repSectionExerciseID: UUID?
    var exerciseID: UUID?
    var exerciseNameSnapshot: String?
    var setIndex: Int
    var reps: Int
    var weight: Double
    var weightUnit: String
    var holdSeconds: Int?
    var isBodyweight: Bool?
    var sideRaw: String?
    var repeatIndex: Int
    var equipmentID: UUID?
    var isManualWeight: Bool?
    var loggedAt: Date
    var isCancelled: Bool
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveStepLog: Codable {
    var id: UUID
    var timeSectionStepID: UUID?
    var stepExerciseNameSnapshot: String?
    var plannedDurationSeconds: Int
    var actualDurationSeconds: Int
    var outcomeRaw: String
    var loggedAt: Date
    var sortOrder: Int
    var repeatIndex: Int
    var updatedAt: Date
    var deletedAt: Date?
}

/// No `deletedAt`: `ExerciseSessionNote` is the one model that doesn't conform to
/// `SyncableModel` — it has no sync fields at all, which is precisely why it can only
/// leave the device inside an archive.
struct ArchiveExerciseNote: Codable {
    var id: UUID
    var exerciseID: UUID?
    var exerciseNameSnapshot: String?
    var text: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Result of an import

struct ArchiveImportSummary {
    var inserted: [String: Int] = [:]
    var updated: [String: Int] = [:]
    var skipped: [String: Int] = [:]
    var imagesRestored = 0
    var iconsRestored = 0

    mutating func insert(_ type: String) { inserted[type, default: 0] += 1 }
    mutating func update(_ type: String) { updated[type, default: 0] += 1 }
    mutating func skip(_ type: String) { skipped[type, default: 0] += 1 }

    var totalInserted: Int { inserted.values.reduce(0, +) }
    var totalUpdated: Int { updated.values.reduce(0, +) }
    var totalSkipped: Int { skipped.values.reduce(0, +) }
}

// MARK: - Errors

enum ArchiveError: LocalizedError {
    case notAnArchive
    case unsupportedVersion(found: Int, supported: Int)
    case missingFile(String)
    case corruptFile(String, underlying: String)
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "That file isn't a WorkoutTracker archive."
        case .unsupportedVersion(let found, let supported):
            return "This archive was made by a newer version of the app (format \(found); this version reads up to \(supported)). Update the app and try again."
        case .missingFile(let name):
            return "The archive is incomplete — \(name) is missing."
        case .corruptFile(let name, let underlying):
            return "Couldn't read \(name) from the archive: \(underlying)"
        case .zipFailed(let detail):
            return "Couldn't read or write the archive file: \(detail)"
        }
    }
}
