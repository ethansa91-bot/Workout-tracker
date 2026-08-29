import Foundation

/// What actually travels between two users when a workout is shared.
///
/// The workout itself reuses the archive DTOs unchanged — they already carry every
/// field and are already `Codable` both ways. What's added is the **catalog manifest**:
/// the workout's steps reference exercises by UUID, and an exercise in turn references
/// muscles, equipment and categories the recipient may not have.
///
/// Carrying that whole closure alongside the workout is what lets a downloaded workout
/// arrive complete — exercises with their muscles, their equipment and their photo —
/// rather than as a set of bare names. Identity is resolved on the receiving side by
/// `CatalogImportPlanner`, which matches on id first and normalized name second.
struct SharedWorkoutPayload: Codable {
    /// Bumped only for breaking changes; the importer refuses anything higher.
    var formatVersion: Int
    var workout: ArchiveWorkout
    /// Every exercise the workout references, by the publisher's ids.
    var exercises: [ArchiveExercise]
    /// All equipment attached to those exercises — not merely the one reachable through
    /// `RepSectionExercise.preferredEquipment`, which is what v1 sent.
    var equipment: [ArchiveEquipment]
    /// Defaulted, so a v1 payload written before the catalog travelled still decodes.
    var muscles: [ArchiveMuscle] = []
    var muscleCategories: [ArchiveMuscleCategory] = []
    var exerciseCategories: [ArchiveExerciseCategory] = []
    /// Only ever applied to equipment the import creates — see `CatalogMerge`.
    var weightCombos: [ArchiveWeightCombo] = []

    /// v2 added the catalog closure and exercise photos. A v1 app meeting a v2 payload
    /// takes the existing `unsupportedVersion` path and is told to update, which is the
    /// correct outcome — it genuinely cannot represent what's inside.
    static let currentVersion = 2
}

/// A payload plus the image bytes that can't live inside it.
///
/// Generated exercise photos are files in Application Support, not fields on a record,
/// so they travel as a separate zipped `CKAsset` keyed by
/// `ArchiveExercise.generatedImageFileName` — exactly the arrangement the archive format
/// already uses for its `images/` directory. Keeping them out of the JSON is what lets
/// the `payload` asset stay plain JSON that older builds can still parse.
struct SharedWorkoutBundle {
    var payload: SharedWorkoutPayload
    /// JPEG bytes, keyed by filename. Empty for a v1 payload.
    var images: [String: Data] = [:]
}

/// A published workout as it appears in a list, without fetching its payload.
///
/// Browsing someone's workouts should not download every one of them, so the record
/// carries enough metadata to render a row and the payload stays in a `CKAsset` that is
/// only fetched when a specific workout is opened.
struct SharedWorkoutSummary: Identifiable, Hashable {
    /// The CloudKit record name.
    let id: String
    let ownerRecordName: String
    /// The publisher's local workout id — stable across republishes, so re-publishing
    /// updates the same record rather than accumulating duplicates.
    let workoutID: UUID
    let name: String
    let sectionCount: Int
    let summary: String
    let updatedAt: Date
}

/// Another user, resolved from their share code.
struct SharedProfile: Hashable {
    let recordName: String
    let shareCode: String
    let displayName: String
}

/// What a download will do to the recipient's library, computed before anything is
/// written so the review screen can state it plainly and the user can change it.
struct SharedWorkoutPlan: Identifiable {
    /// One per workout being saved. Several at once share a single catalog plan on
    /// purpose: two workouts referencing the same exercise must resolve it the same way,
    /// and asking twice would let them disagree.
    let bundles: [SharedWorkoutBundle]
    /// Photos merged across every bundle, keyed by the publisher's filename.
    let images: [String: Data]
    var catalog: CatalogImportPlan

    let id = UUID()

    var workoutNames: [String] { bundles.map(\.payload.workout.name) }

    var workoutCount: Int { bundles.count }

    /// Sections across every workout in the plan.
    var sectionCount: Int {
        bundles.reduce(0) { $0 + $1.payload.workout.sections.filter { $0.deletedAt == nil }.count }
    }

    /// Nothing to decide — every incoming row matched something identical, so the review
    /// screen would be an empty page in front of a button.
    var needsReview: Bool { catalog.needsReview }

    /// A workout name for one-line confirmations, quoting the single name when there is
    /// only one and counting otherwise.
    var displayTitle: String {
        guard let first = workoutNames.first else { return "" }
        return bundles.count == 1 ? first : "\(bundles.count) workouts"
    }

    init(bundles: [SharedWorkoutBundle], catalog: CatalogImportPlan) {
        self.bundles = bundles
        self.catalog = catalog
        // Later bundles win on a filename clash, which can only happen when two
        // publishers' exercises share a generated-image name — the bytes are equivalent
        // either way, since the name is derived from the exercise id.
        self.images = bundles.reduce(into: [String: Data]()) { merged, bundle in
            merged.merge(bundle.images) { _, new in new }
        }
    }
}

enum SharingError: LocalizedError {
    case notSignedIn
    case offline
    case codeNotFound(String)
    case invalidCode
    case unsupportedVersion(found: Int, supported: Int)
    case payloadUnreadable(String)
    case cannotFollowSelf

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to iCloud in Settings to share workouts."
        case .offline:
            return "You're offline. Connect to the internet and try again."
        case .codeNotFound(let code):
            return "No one found with the code \(code). Check it and try again."
        case .invalidCode:
            return "That doesn't look like a share code. Codes are 8 characters, like ABCD-3F7K."
        case .unsupportedVersion(let found, let supported):
            return "This workout was shared from a newer version of the app (format \(found); this version reads up to \(supported)). Update to download it."
        case .payloadUnreadable(let detail):
            return "That shared workout couldn't be read: \(detail)"
        case .cannotFollowSelf:
            return "That's your own share code."
        }
    }
}
