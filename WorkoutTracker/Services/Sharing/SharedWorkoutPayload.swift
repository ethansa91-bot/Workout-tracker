import Foundation

/// What actually travels between two users when a workout is shared.
///
/// The workout itself reuses the archive DTOs unchanged — they already carry every
/// field and are already `Codable` both ways. What's added is the **exercise manifest**:
/// the workout's steps reference exercises by UUID, and those UUIDs are only meaningful
/// inside the publisher's own store. Two people's catalogs are seeded independently, so
/// the same "Bench Press" has a different id for each of them.
///
/// Carrying the referenced exercises alongside the workout is what lets the recipient
/// match them by name and create anything genuinely missing, instead of receiving a
/// workout full of dangling references.
struct SharedWorkoutPayload: Codable {
    /// Bumped only for breaking changes; the importer refuses anything higher.
    var formatVersion: Int
    var workout: ArchiveWorkout
    /// Every exercise the workout references, by the publisher's ids.
    var exercises: [ArchiveExercise]
    /// Only the equipment reachable through `RepSectionExercise.preferredEquipment` —
    /// the sole catalog type a workout touches besides exercises.
    var equipment: [ArchiveEquipment]

    static let currentVersion = 1
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
/// written so the confirmation can state it plainly.
struct SharedWorkoutPlan {
    let payload: SharedWorkoutPayload
    /// Exercises matched to rows already in the recipient's catalog.
    let matchedExerciseNames: [String]
    /// Exercises that will be created as custom entries. Named in the confirmation —
    /// adding rows to someone's catalog is not something to do silently.
    let newExerciseNames: [String]

    var workoutName: String { payload.workout.name }
    var sectionCount: Int { payload.workout.sections.filter { $0.deletedAt == nil }.count }
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
