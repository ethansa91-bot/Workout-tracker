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
    /// Defaulted so archives written before execution types existed still decode.
    var executionTypes: [ArchiveExecutionType] = []
    var progressionGroups: [ArchiveProgressionGroup] = []
    var progressionSteps: [ArchiveProgressionStep] = []
    /// Workout-scoped rather than catalog-scoped, but this is where every by-id lookup
    /// table lives and the importer resolves them all in one pass.
    var workoutTags: [ArchiveWorkoutTag] = []
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

/// A progression ladder. `reachedLevel` is user progress, not catalog data — it travels
/// here because a backup must be faithful, and is deliberately dropped on a shared import.
struct ArchiveProgressionGroup: Codable {
    var id: UUID
    var reachedLevel: Int
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveProgressionStep: Codable {
    var id: UUID
    var groupID: UUID?
    var exerciseID: UUID?
    var level: Int
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveWorkoutTag: Codable {
    var id: UUID
    var name: String
    var isCustom: Bool
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveExecutionType: Codable {
    var id: UUID
    var name: String
    var isCustom: Bool
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
    /// Optional, not `Bool = false`: synthesized `Decodable` ignores a default value and
    /// throws `keyNotFound` for a missing non-optional key, so an archive written before
    /// this field existed would fail to open.
    var defaultsToBodyweight: Bool? = nil
    var equipmentIDs: [UUID]
    /// Defaulted, like every field added after format v1 — an older archive simply has no
    /// execution types, which is a correct reading of it rather than a missing one.
    var executionTypeIDs: [UUID] = []
    var separateRecordsPerExecutionType: Bool = false
    var muscleIDs: [UUID]
    var categoryIDs: [UUID]
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchivePersonalRecord: Codable {
    var id: UUID
    var exerciseID: UUID?
    var equipmentID: UUID?
    var executionTypeID: UUID? = nil
    var weightUnit: String?
    var isBodyweight: Bool
    /// Optional, not `Bool = false`: synthesized `Decodable` ignores a default value and
    /// throws `keyNotFound` for a missing non-optional key, so an archive written before
    /// this field existed would fail to open.
    var isFollowAlong: Bool? = nil
    var trackingModeRaw: String
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    /// Optional, like every field added after v1: synthesized `Decodable` throws
    /// `keyNotFound` for a missing non-optional key even when it has a default, so an
    /// archive written before this existed would fail to open. `nil` means an ordinary
    /// exercise record, which is every record written before section records existed.
    var sectionRecordGroupID: UUID? = nil
    var sectionRecordKindRaw: String? = nil
    var sectionRecordName: String? = nil
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchivePersonalRecordEntry: Codable {
    var id: UUID
    var recordID: UUID?
    var exerciseID: UUID?
    var equipmentID: UUID?
    var executionTypeID: UUID? = nil
    var weightUnit: String?
    var isBodyweight: Bool
    /// Optional, not `Bool = false`: synthesized `Decodable` ignores a default value and
    /// throws `keyNotFound` for a missing non-optional key, so an archive written before
    /// this field existed would fail to open.
    var isFollowAlong: Bool? = nil
    var trackingModeRaw: String
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?
    /// Optional, like every field added after v1: synthesized `Decodable` throws
    /// `keyNotFound` for a missing non-optional key even when it has a default, so an
    /// archive written before this existed would fail to open. `nil` means an ordinary
    /// exercise record, which is every record written before section records existed.
    var sectionRecordGroupID: UUID? = nil
    var sectionRecordKindRaw: String? = nil
    var sectionRecordName: String? = nil
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
    var tagIDs: [UUID] = []
    var sections: [ArchiveSection]
    /// Optional for the same reason `progressionEnabled`-adjacent fields elsewhere are
    /// — an archive written before version history existed would otherwise fail to
    /// open entirely.
    var versionGroupID: UUID? = nil
    var isSupersededVersion: Bool? = nil
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
    /// Optional, not `Int = 0`: Swift's synthesized `Decodable` ignores a default value
    /// and throws `keyNotFound` for a missing non-optional key, so an archive written
    /// before this field existed would fail to open. `nil` reads as no get-ready.
    var getReadySeconds: Int? = nil
    /// Optional for the same reason `getReadySeconds` is. `nil` reads as `true`, which is
    /// what every section written before this existed did.
    var repeatsGetReadyEachPass: Bool? = nil
    var sectionRestSeconds: Int? = nil
    /// Optional for the same reason `getReadySeconds` is. `nil` reads as `false`/absent,
    /// which is every section written before records and to-failure existed.
    var emomToFailure: Bool? = nil
    var tracksRecord: Bool? = nil
    /// The record identity, carried so a restored section rejoins the record it was
    /// already filing under rather than starting a second one.
    var recordGroupID: UUID? = nil
    var recordLockedAt: Date? = nil
    /// Only ever set on a template — sections inside a workout are filed under it.
    var tagIDs: [UUID] = []
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
    var executionTypeID: UUID? = nil
    var sideRaw: String? = nil
    var preferredEquipmentID: UUID? = nil
    /// Optional, not `Bool = false`: synthesized `Decodable` ignores a default value and
    /// throws `keyNotFound` for a missing non-optional key, so an archive written before
    /// this field existed would fail to open.
    var prefersBodyweight: Bool? = nil
    /// Optional for the same reason `prefersBodyweight` is — an archive written before
    /// this existed would otherwise fail to open entirely.
    var startingWeight: Double? = nil
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
    var executionTypeID: UUID? = nil
    var progressionEnabled: Bool = true
    /// Optional for the same reason `executionTypeID` is — an archive written before
    /// these existed would otherwise fail to open entirely.
    var startingWeight: Double? = nil
    var startingReps: Int? = nil
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveQuickExercise: Codable {
    var id: UUID
    var sortOrder: Int
    var exerciseID: UUID?
    var executionTypeID: UUID? = nil
    var targetReps: Int = 0
    var sideRaw: String? = nil
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
    /// Optional: sessions archived before this existed simply decode as "not resting,"
    /// which is what `WorkoutSession.isSectionResting`'s own stored default means too.
    var isSectionResting: Bool?
    var supersededBySessionId: UUID?
    var setLogs: [ArchiveSetLog]
    var stepLogs: [ArchiveStepLog]
    /// Defaulted rather than optional because it is a collection: an absent key decodes
    /// as empty, which is exactly right for a session recorded before EMOM/AMRAP results
    /// were kept at all.
    var sectionResultLogs: [ArchiveSectionResultLog] = []
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
    var executionTypeID: UUID? = nil
    var loggedAt: Date
    var isCancelled: Bool
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveStepLog: Codable {
    var id: UUID
    var timeSectionStepID: UUID?
    var stepExerciseNameSnapshot: String?
    var executionTypeID: UUID? = nil
    var plannedDurationSeconds: Int
    var actualDurationSeconds: Int
    var outcomeRaw: String
    var loggedAt: Date
    var sortOrder: Int
    var repeatIndex: Int
    var updatedAt: Date
    var deletedAt: Date?
}

struct ArchiveSectionResultLog: Codable {
    var id: UUID
    var sectionID: UUID?
    var recordGroupID: UUID?
    var sectionNameSnapshot: String
    var sectionTypeRaw: String
    var repeatIndex: Int
    var value: Int
    var loggedAt: Date
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
