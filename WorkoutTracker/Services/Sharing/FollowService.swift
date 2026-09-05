import Foundation
import SwiftData

/// Every path that changes who this user follows.
///
/// Three call sites need identical behaviour — entering a code (`FollowUserSheet`),
/// opening a link (`FollowByLinkSheet`), and the reciprocal sweep — and the interesting
/// part isn't the local row, it's that each one also has to write or withdraw the public
/// `Follow` record that makes the relationship mutual. Keeping that pairing in one place
/// is what stops a view from updating the list and silently forgetting the other half.
@MainActor
enum FollowService {

    /// Shown when the follow landed but the announcement didn't. Both follow entry
    /// points say the same thing, because it's the same situation.
    static let pendingReciprocationNotice = "You're following them. They won't see you as a follower until this device reaches iCloud — it retries on its own."

    // MARK: - Following

    /// A completed follow, and whether the other side has been told yet.
    ///
    /// Two outcomes worth separating: the follow is local and always succeeds or throws
    /// outright, while the public announcement that makes it mutual can fail on its own.
    /// Collapsing them would mean reporting "couldn't follow" for a follow that plainly
    /// did happen.
    struct FollowOutcome {
        let user: FollowedUser
        /// Non-nil when the `Follow` record couldn't be written. The follow stands;
        /// reciprocation is pending until `reassertFollowRecords` retries it.
        let announcementFailure: Error?

        var isFullyMutual: Bool { announcementFailure == nil }
    }

    /// Follows someone, and announces it so their device can follow back.
    ///
    /// The local row is committed **before** the announcement, so a failed announcement
    /// costs reciprocation and never the follow itself. The announcement is awaited
    /// rather than fired into a detached task: it used to be `Task { try? … }`, which
    /// discarded the error and left nothing to retry it, so one blip at follow time left
    /// the relationship one-sided forever with no way to notice.
    @discardableResult
    static func follow(
        _ profile: SharedProfile,
        wasAutoFollowed: Bool = false,
        context: ModelContext
    ) async throws -> FollowOutcome {
        let user = try upsert(profile, wasAutoFollowed: wasAutoFollowed, context: context)
        try context.save()

        do {
            try await SharingService.recordFollow(of: profile.recordName)
            return FollowOutcome(user: user, announcementFailure: nil)
        } catch {
            return FollowOutcome(user: user, announcementFailure: error)
        }
    }

    /// Stops following someone.
    ///
    /// Soft-deletes locally (so the removal reaches this user's other devices) and
    /// withdraws the public `Follow` record (so this user stops appearing in the other
    /// person's follower list). It deliberately does **not** remove this user from that
    /// person's followed list — dropping someone shouldn't reach into their library.
    static func unfollow(_ user: FollowedUser, context: ModelContext) {
        let ownerRecordName = user.ownerRecordName
        SyncDeletion.delete(user, context: context)
        try? context.save()

        Task { try? await SharingService.removeFollow(of: ownerRecordName) }
    }

    // MARK: - Reciprocation

    /// What one reciprocation sweep did, and whether it could run at all.
    ///
    /// The distinction is the whole point: this used to return a bare array, so "nobody
    /// has followed you" and "the query was rejected because `followeeID` isn't marked
    /// queryable in CloudKit" were the same empty result. That is precisely why a broken
    /// setup looked like a working one with no followers.
    struct MutualFollowResult {
        var added: [FollowedUser] = []
        var failure: Error?

        var didFail: Bool { failure != nil }
    }

    /// Finds everyone who has followed this user and follows them back.
    ///
    /// Still never throws — it runs unprompted on foreground and must not interrupt — but
    /// it now reports the failure so the caller can show it somewhere calm.
    @discardableResult
    static func syncMutualFollows(context: ModelContext) async -> MutualFollowResult {
        // Before anything reads the list: a duplicated row would make the same person look
        // unknown to the matching below and get followed a third time.
        removeDuplicates(context: context)

        // Repair first: a `Follow` record lost to an earlier failure is invisible to the
        // other side, and only this user's device can rewrite it.
        await reassertFollowRecordsOncePerLaunch(context: context)

        let followers: [String]
        do {
            // `.typeMissing` is benign here and only here: on a container where nobody
            // has ever followed anyone there is genuinely nothing to reciprocate, and the
            // sweep runs unprompted on every foreground. `SharingSetupCheck` treats the
            // same result as a failure, which is the right call for a check.
            followers = try await SharingService.followerRecordNames().recordNames
        } catch {
            return MutualFollowResult(failure: error)
        }
        guard !followers.isEmpty else { return MutualFollowResult() }

        // Tombstoned rows are included on purpose. Someone the user deliberately
        // unfollowed still has a live `Follow` record pointing here, so matching only
        // live rows would re-add them on every single sweep — the undo would never stick.
        let existing = (try? context.fetch(FetchDescriptor<FollowedUser>())) ?? []
        var byOwner = Dictionary(
            existing.map { ($0.ownerRecordName, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Whether this device has heard anything back from CloudKit yet.
        //
        // On a fresh install the sweep runs long before the private database has delivered
        // this user's own `FollowedUser` rows, so everyone they already follow looks like a
        // stranger who has just followed them: a second row is inserted for each, all of
        // them are announced as new followers, and the originals arrive minutes later
        // beside the copies. That is the reinstall bug — the duplicates and the wall of
        // false "followed you" notices are one cause.
        //
        // So new rows wait for an import. Known rows are still updated, because that costs
        // nothing and is right either way. In the worst case a genuinely new follower is
        // picked up one foreground later, which nobody will notice; `removeDuplicates`
        // above is the net for anything that still slips through.
        let hasImported = CloudKitSyncMonitor.shared.lastImport != nil

        var result = MutualFollowResult()
        for ownerRecordName in followers {
            if let known = byOwner[ownerRecordName] {
                if !known.followsMe {
                    known.followsMe = true
                    known.markDirty()
                }
                continue
            }

            guard hasImported else { continue }

            // No row at all, so this is genuinely someone new. Their profile supplies the
            // name and code; without it there'd be nothing to show but a record name.
            guard let profile = try? await SharingService.profile(ownerRecordName: ownerRecordName) else {
                continue
            }

            guard let user = try? upsert(profile, wasAutoFollowed: true, context: context) else { continue }
            user.followsMe = true
            byOwner[ownerRecordName] = user
            result.added.append(user)

            // Follow them back publicly too. Best-effort on purpose: the local row is
            // what the user sees, and `reassertFollowRecords` rewrites this on a later
            // launch if it fails. Deliberately not recorded as `result.failure`, which
            // means "couldn't check for followers" and would misreport this.
            try? await SharingService.recordFollow(of: ownerRecordName)
        }

        try? context.save()
        return result
    }

    // MARK: - Followed workout updates

    /// What one update-detection sweep found, and whether it could run at all — same
    /// shape as `MutualFollowResult`, for the same reason.
    struct WorkoutUpdateResult {
        var updated: [Workout] = []
        var failure: Error?
    }

    /// Finds every downloaded workout whose publisher has re-published since it was last
    /// saved or merged.
    ///
    /// Grouped by publisher rather than queried per workout: two workouts from the same
    /// person cost one `publishedWorkouts` call between them, not two. A workout counts as
    /// updated when the summary's `updatedAt` is strictly newer than what this copy last
    /// recorded — `Workout.sourceUpdatedAt`, stamped at download time and again whenever
    /// an update is actually applied, so a workout that's already caught up (or was just
    /// merged) doesn't keep re-appearing every foreground.
    @discardableResult
    static func syncWorkoutUpdates(context: ModelContext) async -> WorkoutUpdateResult {
        let downloaded = ((try? context.fetch(FetchDescriptor<Workout>())) ?? [])
            .filter { $0.deletedAt == nil && $0.sourceOwnerRecordName != nil && $0.clonedFromWorkoutId != nil }
        guard !downloaded.isEmpty else { return WorkoutUpdateResult() }

        var result = WorkoutUpdateResult()
        var summariesByOwner: [String: [SharedWorkoutSummary]] = [:]
        for ownerRecordName in Set(downloaded.compactMap(\.sourceOwnerRecordName)) {
            do {
                summariesByOwner[ownerRecordName] = try await SharingService.publishedWorkouts(ownerRecordName: ownerRecordName)
            } catch {
                result.failure = error
            }
        }

        for workout in downloaded {
            guard let ownerRecordName = workout.sourceOwnerRecordName,
                  let publisherWorkoutID = workout.clonedFromWorkoutId,
                  let summaries = summariesByOwner[ownerRecordName],
                  let match = summaries.first(where: { $0.workoutID == publisherWorkoutID })
            else { continue }
            let lastSeen = workout.sourceUpdatedAt ?? .distantPast
            guard match.updatedAt > lastSeen else { continue }
            result.updated.append(workout)
        }
        return result
    }

    // MARK: - Duplicates

    /// Collapses rows describing the same person into one.
    ///
    /// SwiftData's CloudKit mirroring can't enforce uniqueness, so two rows for one person
    /// coexist happily — which is exactly what a reinstall produces when the sweep inserts
    /// a follow before the synced-down original arrives. Both then show in the list, and
    /// the copy carries `wasAutoFollowed`, so it also announces someone the user has
    /// followed for months as a brand-new follower.
    ///
    /// Keyed on `ownerRecordName` — the CloudKit identity, and what "the same person"
    /// actually means. A second pass catches rows sharing a `shareCode`, which is the same
    /// person seen through a stale record name; empty codes are skipped, since matching on
    /// those would merge everyone who has never set one into a single row.
    ///
    /// Hard-deletes the losers rather than tombstoning them, for the reason
    /// `CatalogReconciliation.dedupe` gives: a tombstone would leave the redundant row
    /// present-but-hidden and still syncing, which is the opposite of removing a duplicate.
    @discardableResult
    static func removeDuplicates(context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<FollowedUser>())) ?? []
        guard all.count > 1 else { return 0 }

        var removed = 0
        removed += collapse(Dictionary(grouping: all.filter { !$0.ownerRecordName.isEmpty }, by: \.ownerRecordName), context: context)

        let survivors = (try? context.fetch(FetchDescriptor<FollowedUser>())) ?? []
        removed += collapse(Dictionary(grouping: survivors.filter { !$0.shareCode.isEmpty }, by: \.shareCode), context: context)

        if removed > 0 { try? context.save() }
        return removed
    }

    private static func collapse(_ groups: [String: [FollowedUser]], context: ModelContext) -> Int {
        var removed = 0
        for (_, group) in groups where group.count > 1 {
            // The most recently touched row wins. Unfollowing stamps `updatedAt`, so this
            // is what keeps a deliberate removal from being undone by an older live copy
            // that happens to still be sitting in the store.
            //
            // The id breaks a tie. Both rows sync, so two devices deduping the same pair
            // read the same `updatedAt` — but if those are equal and each device sorted
            // differently, they would keep opposite rows and delete each other's survivor,
            // leaving nothing. `CatalogReconciliation` avoids this by taking the oldest for
            // the same reason: what matters is that every device picks alike.
            guard let survivor = group.max(by: { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.updatedAt < rhs.updatedAt
            }) else { continue }

            for duplicate in group where duplicate !== survivor {
                // The earliest of them is when this person was actually followed; the copy
                // carries whenever the sweep happened to mint it.
                survivor.followedAt = min(survivor.followedAt, duplicate.followedAt)
                survivor.followsMe = survivor.followsMe || duplicate.followsMe
                // Either row having seen the notice means it has been seen. Without this a
                // reinstall re-announces people the user acknowledged long ago.
                survivor.noticeAcknowledged = survivor.noticeAcknowledged || duplicate.noticeAcknowledged
                if survivor.displayName.isEmpty { survivor.displayName = duplicate.displayName }
                if survivor.shareCode.isEmpty { survivor.shareCode = duplicate.shareCode }
                context.delete(duplicate)
                removed += 1
            }
            survivor.markDirty()
        }
        return removed
    }

    // MARK: - Repair

    /// Once per process, rewrite this user's `Follow` record for everyone they follow.
    ///
    /// This is the repair path that was missing. `recordFollow` can fail at follow time
    /// for entirely ordinary reasons — offline, a schema not yet deployed — and nothing
    /// on the other side can tell. Record ids are deterministic
    /// (`follow_<follower>_<followee>`), so rewriting is idempotent and costs one small
    /// write per followed person, once per launch.
    private static var hasReassertedThisLaunch = false

    private static func reassertFollowRecordsOncePerLaunch(context: ModelContext) async {
        guard !hasReassertedThisLaunch else { return }
        hasReassertedThisLaunch = true
        await reassertFollowRecords(context: context)
    }

    /// Exposed for the setup check, which runs it on demand.
    static func reassertFollowRecords(context: ModelContext) async {
        let followed = ((try? context.fetch(FetchDescriptor<FollowedUser>())) ?? [])
            .filter { $0.deletedAt == nil }
        for user in followed {
            try? await SharingService.recordFollow(of: user.ownerRecordName)
        }
    }

    /// Re-reads the names of everyone this user follows.
    ///
    /// `displayName` is captured once when the follow happens, so without this a person
    /// who set their name after being followed would show as a share code forever.
    static func refreshDisplayNames(context: ModelContext) async {
        let followed = ((try? context.fetch(FetchDescriptor<FollowedUser>())) ?? [])
            .filter { $0.deletedAt == nil }
        guard !followed.isEmpty else { return }

        var savedAnything = false
        for user in followed {
            guard let profile = try? await SharingService.profile(ownerRecordName: user.ownerRecordName) else {
                continue
            }

            var changed = false
            if profile.displayName != user.displayName {
                user.displayName = profile.displayName
                changed = true
            }
            // Codes rotate; the stored one is only ever display, never a lookup key.
            if !profile.shareCode.isEmpty && profile.shareCode != user.shareCode {
                user.shareCode = profile.shareCode
                changed = true
            }

            if changed {
                user.markDirty()
                savedAnything = true
            }
        }

        if savedAnything { try? context.save() }
    }

    // MARK: - Helpers

    /// Revives an existing row rather than creating a second one — including one
    /// previously unfollowed, which is a tombstone rather than an absence.
    private static func upsert(
        _ profile: SharedProfile,
        wasAutoFollowed: Bool,
        context: ModelContext
    ) throws -> FollowedUser {
        let ownerRecordName = profile.recordName
        let descriptor = FetchDescriptor<FollowedUser>(
            predicate: #Predicate { $0.ownerRecordName == ownerRecordName }
        )

        if let match = try context.fetch(descriptor).first {
            match.deletedAt = nil
            match.shareCode = profile.shareCode
            match.displayName = profile.displayName
            match.wasAutoFollowed = wasAutoFollowed
            match.noticeAcknowledged = !wasAutoFollowed
            match.markDirty()
            return match
        }

        let user = FollowedUser(
            ownerRecordName: ownerRecordName,
            shareCode: profile.shareCode,
            displayName: profile.displayName
        )
        user.wasAutoFollowed = wasAutoFollowed
        // A follow the user performed themselves needs no announcement.
        user.noticeAcknowledged = !wasAutoFollowed
        context.insert(user)
        return user
    }
}
