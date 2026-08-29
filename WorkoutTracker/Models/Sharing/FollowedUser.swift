import Foundation
import SwiftData

/// Someone whose shared workouts this user can browse.
///
/// Following is **mutual**: following someone writes a `Follow` record in the public
/// database, their device finds it on its next sweep, and it follows back automatically.
/// So a row here can arrive two ways — this user entered a code or opened a link, or
/// `FollowService.syncMutualFollows` added it on their behalf (`wasAutoFollowed`).
///
/// Unfollowing is one-sided by design: it soft-deletes this row and withdraws this
/// user's `Follow` record, but never touches the other person's list. The tombstone is
/// also what stops the sweep from re-adding someone the user deliberately removed, so
/// `deletedAt` here is load-bearing beyond ordinary sync.
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
    /// A `Follow` record from them to this user exists — i.e. the relationship is mutual
    /// rather than this user having followed them without reciprocation (which happens
    /// when they unfollowed, or when the sweep hasn't reached their device yet).
    var followsMe: Bool = false
    /// Created by `FollowService.syncMutualFollows` rather than by this user entering a
    /// code, which is what the "X followed you" notice reports.
    var wasAutoFollowed: Bool = false
    /// The auto-follow notice has been shown, so it isn't shown again on every launch.
    var noticeAcknowledged: Bool = false
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
        self.followsMe = false
        self.wasAutoFollowed = false
        self.noticeAcknowledged = false
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
