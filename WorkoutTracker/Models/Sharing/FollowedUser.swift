import Foundation
import SwiftData

/// Someone whose shared workouts this user can browse.
///
/// Following is entirely one-sided and local: the person being followed is never told,
/// and there is no record of them having a follower. The only revoke available to them
/// is rotating their code, which orphans every follower at once.
///
/// Modeled in SwiftData rather than `UserDefaults` so the list survives a reinstall and
/// reaches the user's other devices through the existing private-database sync — the
/// same reason every other durable list here is a `@Model`.
@Model
final class FollowedUser: SyncableModel {
    var id: UUID = UUID()
    /// The followed user's CloudKit `userRecordID.recordName` — the stable identity, and
    /// what published workouts are queried by.
    var ownerRecordName: String = ""
    /// The code as it was entered. Kept for display and so a stale follow can say which
    /// code stopped working, but never used as the lookup key after the initial resolve:
    /// codes rotate, record names don't.
    var shareCode: String = ""
    var displayName: String = ""
    var followedAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        ownerRecordName: String,
        shareCode: String,
        displayName: String
    ) {
        self.id = id
        self.ownerRecordName = ownerRecordName
        self.shareCode = shareCode
        self.displayName = displayName
        self.followedAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
    }

    /// Falls back to the code when the publisher hasn't set a name, so a row is never
    /// blank.
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ShareCode.format(shareCode) : trimmed
    }
}
