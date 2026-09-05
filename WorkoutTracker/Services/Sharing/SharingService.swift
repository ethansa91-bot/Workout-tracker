import CloudKit
import Foundation
import ZIPFoundation

/// All access to the CloudKit **public** database.
///
/// This is deliberately separate from everything in `Sync/`. That layer observes
/// SwiftData's automatic mirroring to the user's **private** database — their own
/// devices, no one else's. Sharing between different people can only happen in the
/// public database, which SwiftData cannot mirror to, so every call here is hand-written
/// CloudKit running alongside the existing sync rather than replacing any part of it.
///
/// Visibility is code-gated, not access-controlled: records are world-readable, and what
/// stops a stranger reading someone's workouts is that they don't have the code. The UI
/// says so plainly — this is "unlisted", not "private".
enum SharingService {

    // MARK: - Record types and keys

    private enum RecordType {
        static let profile = "Profile"
        static let sharedWorkout = "SharedWorkout"
        static let follow = "Follow"
    }

    private enum ProfileKey {
        static let shareCode = "shareCode"
        static let displayName = "displayName"
        static let updatedAt = "updatedAt"
    }

    private enum FollowKey {
        static let followerID = "followerID"
        static let followeeID = "followeeID"
        static let createdAt = "createdAt"
    }

    private enum WorkoutKey {
        static let ownerID = "ownerID"
        static let workoutID = "workoutID"
        static let name = "name"
        static let sectionCount = "sectionCount"
        static let summary = "summary"
        static let payload = "payload"
        /// A zip of the generated exercise photos. A separate asset rather than bytes
        /// inside `payload`, so `payload` stays plain JSON an older build can still read.
        static let images = "images"
        static let updatedAt = "updatedAt"
    }

    private static var container: CKContainer {
        // The explicit identifier, never `CKContainer.default()` — the same reasoning
        // documented in `SyncDiagnosticsView`.
        CKContainer(identifier: CloudKitContainer.identifier)
    }

    private static var database: CKDatabase { container.publicCloudDatabase }

    // MARK: - Identity

    /// The signed-in user's CloudKit record name — stable per container, and the identity
    /// everything here hangs off. No login, no account, nothing personal.
    static func myRecordName() async throws -> String {
        guard NetworkReachability.shared.isOnline else { throw SharingError.offline }
        let status = try await container.accountStatus()
        guard status == .available else { throw SharingError.notSignedIn }
        return try await container.userRecordID().recordName
    }

    /// This user's profile, creating it with a fresh code on first use.
    ///
    /// The `Profile` record — not `UserDefaults` — is the source of truth for the code,
    /// because `UserDefaults` doesn't travel between the user's own devices and two
    /// devices generating two different codes would be its own bug. `AppSettings` caches
    /// it only so the UI has something to show before the network answers.
    @discardableResult
    static func ensureProfile() async throws -> SharedProfile {
        let recordName = try await myRecordName()
        let recordID = profileRecordID(for: recordName)

        if let existing = try? await database.record(for: recordID),
           let code = existing[ProfileKey.shareCode] as? String, !code.isEmpty {
            let profile = SharedProfile(
                recordName: recordName,
                shareCode: code,
                displayName: existing[ProfileKey.displayName] as? String ?? ""
            )
            AppSettings.shareCode = code
            AppSettings.displayName = profile.displayName
            return profile
        }

        let record = CKRecord(recordType: RecordType.profile, recordID: recordID)
        let code = ShareCode.generate()
        record[ProfileKey.shareCode] = ShareCode.normalize(code)
        // A name the user hasn't set yet, not a name they cleared — preserved rather than
        // overwritten if a local cache already holds one from an earlier device.
        record[ProfileKey.displayName] = AppSettings.displayName ?? ""
        record[ProfileKey.updatedAt] = Date()

        let saved = try await database.save(record)
        let stored = saved[ProfileKey.shareCode] as? String ?? code
        let name = saved[ProfileKey.displayName] as? String ?? ""
        AppSettings.shareCode = stored
        AppSettings.displayName = name
        return SharedProfile(recordName: recordName, shareCode: stored, displayName: name)
    }

    /// Replaces this user's code. Everyone currently following them stops resolving —
    /// this is the only revoke available, and it is all-or-nothing.
    @discardableResult
    static func rotateCode() async throws -> SharedProfile {
        let recordName = try await myRecordName()
        let recordID = profileRecordID(for: recordName)
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: RecordType.profile, recordID: recordID)

        let code = ShareCode.normalize(ShareCode.generate())
        record[ProfileKey.shareCode] = code
        record[ProfileKey.updatedAt] = Date()

        let saved = try await database.save(record)
        let name = saved[ProfileKey.displayName] as? String ?? ""
        AppSettings.shareCode = code
        AppSettings.displayName = name
        return SharedProfile(recordName: recordName, shareCode: code, displayName: name)
    }

    /// Sets the name everyone following this user sees.
    ///
    /// Creates the profile if it doesn't exist yet rather than returning silently, which
    /// is what this used to do — a user who set a name before `ensureProfile` had ever
    /// completed would have had it quietly discarded.
    static func setDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordName = try await myRecordName()
        let recordID = profileRecordID(for: recordName)

        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: RecordType.profile, recordID: recordID)
            record[ProfileKey.shareCode] = ShareCode.normalize(ShareCode.generate())
        }

        record[ProfileKey.displayName] = trimmed
        record[ProfileKey.updatedAt] = Date()
        let saved = try await database.save(record)

        AppSettings.displayName = trimmed
        if let code = saved[ProfileKey.shareCode] as? String { AppSettings.shareCode = code }
    }

    /// One person's profile, fetched **by record id rather than by query**.
    ///
    /// That distinction matters: `lookup(code:)` needs `shareCode` to be marked queryable
    /// in the CloudKit Console, but this needs no index at all, because the profile id is
    /// derived from the record name. It's how a reciprocal follow resolves someone who
    /// was never looked up by code, and how a stale `displayName` gets refreshed.
    static func profile(ownerRecordName: String) async throws -> SharedProfile? {
        guard NetworkReachability.shared.isOnline else { throw SharingError.offline }
        guard let record = try? await database.record(for: profileRecordID(for: ownerRecordName)) else {
            return nil
        }
        return SharedProfile(
            recordName: ownerRecordName,
            shareCode: record[ProfileKey.shareCode] as? String ?? "",
            displayName: record[ProfileKey.displayName] as? String ?? ""
        )
    }

    // MARK: - Follows

    /// Announces that this user follows `ownerRecordName`, so that person's device can
    /// find them and follow back.
    ///
    /// The record id is deterministic, so following, unfollowing and re-following the
    /// same person overwrites one record instead of accumulating them.
    static func recordFollow(of ownerRecordName: String) async throws {
        let me = try await myRecordName()
        guard me != ownerRecordName else { return }

        let record = CKRecord(
            recordType: RecordType.follow,
            recordID: CKRecord.ID(recordName: followRecordName(follower: me, followee: ownerRecordName))
        )
        record[FollowKey.followerID] = me
        record[FollowKey.followeeID] = ownerRecordName
        record[FollowKey.createdAt] = Date()

        // `.allKeys` rather than a plain save: re-following someone overwrites a record
        // this user already owns, and the default policy would reject it on the change tag.
        let operation = CKModifyRecordsOperation(recordsToSave: [record])
        operation.savePolicy = .allKeys
        operation.isAtomic = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { continuation.resume(with: $0) }
            database.add(operation)
        }
    }

    /// Withdraws this user from someone's follower list. Deliberately does not touch that
    /// person's own `Follow` record — unfollowing is one-sided.
    static func removeFollow(of ownerRecordName: String) async throws {
        let me = try await myRecordName()
        let recordID = CKRecord.ID(recordName: followRecordName(follower: me, followee: ownerRecordName))
        _ = try? await database.deleteRecord(withID: recordID)
    }

    /// The outcome of looking up who follows this user.
    ///
    /// The two cases used to be flattened into an empty array, and that was a real
    /// mistake: a `Follow` record type that doesn't exist yet and a user nobody has
    /// followed produce the same empty result, so a container missing the type entirely
    /// looked exactly like a working one. The background sweep is happy to treat them
    /// alike; a setup check must not.
    enum FollowerLookup {
        case followers([String])
        /// The `Follow` type doesn't exist in this environment. CloudKit creates a custom
        /// type on the first successful save, so this means no `Follow` record has ever
        /// been written here — not that this user has no followers.
        case typeMissing

        /// For callers that genuinely don't care about the difference.
        var recordNames: [String] {
            if case .followers(let names) = self { return names }
            return []
        }
    }

    /// Everyone who has followed this user. `followeeID` must be marked queryable in the
    /// CloudKit Console, exactly like `Profile.shareCode`.
    static func followerRecordNames() async throws -> FollowerLookup {
        guard NetworkReachability.shared.isOnline else { throw SharingError.offline }
        let me = try await myRecordName()

        let query = CKQuery(
            recordType: RecordType.follow,
            predicate: NSPredicate(format: "%K == %@", FollowKey.followeeID, me)
        )

        let matches: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (matches, _) = try await database.records(
                matching: query,
                desiredKeys: [FollowKey.followerID, FollowKey.followeeID]
            )
        } catch let error as CKError where error.code == .unknownItem {
            // Reported rather than swallowed. Whether this is benign is the caller's
            // decision, and the two callers disagree.
            return .typeMissing
        }

        let followers = matches.compactMap { _, result -> String? in
            guard let record = try? result.get(),
                  let follower = record[FollowKey.followerID] as? String,
                  follower != me,
                  // Never surface the schema probe as a person.
                  follower != schemaProbeRecordName
            else { return nil }
            return follower
        }
        return .followers(followers)
    }

    /// Writes and immediately deletes a throwaway `Follow` record, so the record type
    /// comes into existence.
    ///
    /// This exists to break a genuine chicken-and-egg: CloudKit creates a custom record
    /// type only on the first successful save, and the Console can't add a queryable
    /// index to a type that doesn't exist — so follow-back can't be configured until
    /// something has written a `Follow` record. Nothing else in the app can be relied on
    /// to do that first, because following someone is exactly what's broken until it's
    /// configured.
    ///
    /// Doubles as a test of the write path, which is the likelier root cause when the
    /// type is missing despite people having followed each other.
    ///
    /// Only works in **Development**. Production schemas are immutable outside a deploy,
    /// and the resulting error is the correct answer there rather than a fault.
    static func createFollowSchemaProbe() async throws {
        let me = try await myRecordName()
        let recordID = CKRecord.ID(
            recordName: followRecordName(follower: me, followee: schemaProbeRecordName)
        )

        let record = CKRecord(recordType: RecordType.follow, recordID: recordID)
        record[FollowKey.followerID] = me
        record[FollowKey.followeeID] = schemaProbeRecordName
        record[FollowKey.createdAt] = Date()

        let operation = CKModifyRecordsOperation(recordsToSave: [record])
        operation.savePolicy = .allKeys
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { continuation.resume(with: $0) }
            database.add(operation)
        }

        // Best-effort cleanup. A leftover is inert anyway: no real account has this
        // record name, and `followerRecordNames` filters it out explicitly.
        _ = try? await database.deleteRecord(withID: recordID)
    }

    /// Deliberately not a valid CloudKit user record name, so it can never collide with a
    /// real account.
    private static let schemaProbeRecordName = "_schemaProbe"

    /// Resolves a share code to the person who owns it. The `shareCode` field must be
    /// marked queryable in the CloudKit Console or this returns nothing.
    static func lookup(code: String) async throws -> SharedProfile {
        guard NetworkReachability.shared.isOnline else { throw SharingError.offline }
        guard ShareCode.isPlausible(code) else { throw SharingError.invalidCode }

        let normalized = ShareCode.normalize(code)
        let query = CKQuery(
            recordType: RecordType.profile,
            predicate: NSPredicate(format: "%K == %@", ProfileKey.shareCode, normalized)
        )

        let matches: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (matches, _) = try await database.records(matching: query, resultsLimit: 1)
        } catch let error as CKError where error.code == .unknownItem {
            // No `Profile` type yet — nobody using this container has set up sharing.
            // Indistinguishable from "that code matches nobody" as far as the user is
            // concerned, and far more useful than a raw CloudKit error.
            throw SharingError.codeNotFound(ShareCode.format(code))
        }

        guard let first = matches.first, let record = try? first.1.get() else {
            throw SharingError.codeNotFound(ShareCode.format(code))
        }

        // The record id is the prefixed profile id; strip the prefix to recover the user
        // record name that published workouts are actually keyed by.
        let ownerRecordName = userRecordName(fromProfileID: record.recordID.recordName)

        let mine = try? await myRecordName()
        guard ownerRecordName != mine else { throw SharingError.cannotFollowSelf }

        return SharedProfile(
            recordName: ownerRecordName,
            shareCode: record[ProfileKey.shareCode] as? String ?? normalized,
            displayName: record[ProfileKey.displayName] as? String ?? ""
        )
    }

    // MARK: - Publishing

    /// Publishes (or re-publishes) one workout. Keyed by the workout's local id, so
    /// publishing the same workout twice updates one record rather than accumulating
    /// copies.
    static func publish(_ bundle: SharedWorkoutBundle) async throws {
        let payload = bundle.payload
        let recordName = try await myRecordName()
        let recordID = CKRecord.ID(recordName: sharedRecordName(owner: recordName, workoutID: payload.workout.id))
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: RecordType.sharedWorkout, recordID: recordID)

        let encoder = JSONEncoder()
        // Matching the archive services, so shared payloads and archives stay comparable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        // Everything staged under one directory so a single defer cleans up both assets;
        // CloudKit has finished reading them by the time `save` returns.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        // A CKAsset rather than a field: CKRecord fields cap around 1MB, and a workout
        // plus its catalog manifest can approach that.
        let payloadURL = staging.appendingPathComponent("payload.json")
        try data.write(to: payloadURL, options: .atomic)

        let sections = payload.workout.sections.filter { $0.deletedAt == nil }
        record[WorkoutKey.ownerID] = recordName
        record[WorkoutKey.workoutID] = payload.workout.id.uuidString
        record[WorkoutKey.name] = payload.workout.name
        record[WorkoutKey.sectionCount] = sections.count as NSNumber
        record[WorkoutKey.summary] = summarize(payload)
        record[WorkoutKey.payload] = CKAsset(fileURL: payloadURL)
        record[WorkoutKey.images] = try imagesAsset(bundle.images, staging: staging)
        record[WorkoutKey.updatedAt] = Date()

        _ = try await database.save(record)
    }

    /// Zips the generated photos into one asset, or clears the field when there are
    /// none — a republish of a workout whose photos were removed must not keep serving
    /// the old ones.
    private static func imagesAsset(_ images: [String: Data], staging: URL) throws -> CKAsset? {
        guard !images.isEmpty else { return nil }

        let directory = staging.appendingPathComponent(ArchiveFormat.imagesDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (fileName, data) in images {
            // The filename is the publisher's; the recipient re-derives its own from the
            // local exercise id when it adopts the picture. See `CatalogMerge.adoptPhoto`.
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        }

        let zipURL = staging.appendingPathComponent("images.zip")
        do {
            // shouldKeepParent: false — entries sit at the zip root, matching how
            // `ArchiveImportService` reads the archive's own images directory.
            try FileManager.default.zipItem(at: directory, to: zipURL, shouldKeepParent: false)
        } catch {
            throw ArchiveError.zipFailed(error.localizedDescription)
        }
        return CKAsset(fileURL: zipURL)
    }

    static func unpublish(workoutID: UUID) async throws {
        let recordName = try await myRecordName()
        let recordID = CKRecord.ID(recordName: sharedRecordName(owner: recordName, workoutID: workoutID))
        _ = try? await database.deleteRecord(withID: recordID)
    }

    /// Which of this user's workouts are currently published — so the publish picker can
    /// show state rather than making the user remember.
    static func myPublishedWorkoutIDs() async throws -> Set<UUID> {
        let recordName = try await myRecordName()
        let summaries = try await publishedWorkouts(ownerRecordName: recordName)
        return Set(summaries.map(\.workoutID))
    }

    // MARK: - Browsing and downloading

    /// Metadata only — the payload asset is deliberately not fetched, so opening
    /// someone's list doesn't download every workout they have.
    static func publishedWorkouts(ownerRecordName: String) async throws -> [SharedWorkoutSummary] {
        guard NetworkReachability.shared.isOnline else { throw SharingError.offline }

        let query = CKQuery(
            recordType: RecordType.sharedWorkout,
            predicate: NSPredicate(format: "%K == %@", WorkoutKey.ownerID, ownerRecordName)
        )
        query.sortDescriptors = [NSSortDescriptor(key: WorkoutKey.updatedAt, ascending: false)]

        let matches: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (matches, _) = try await database.records(
                matching: query,
                desiredKeys: [
                    WorkoutKey.ownerID, WorkoutKey.workoutID, WorkoutKey.name,
                    WorkoutKey.sectionCount, WorkoutKey.summary, WorkoutKey.updatedAt,
                ]
            )
        } catch let error as CKError where error.code == .unknownItem {
            // The record type doesn't exist yet, because nobody has published anything.
            // In Development a type is only created by the first successful save, so
            // querying before then always fails — and "nothing published" is the correct
            // answer here, not an error to show the user.
            return []
        }

        return matches.compactMap { _, result in
            guard let record = try? result.get(),
                  let workoutIDString = record[WorkoutKey.workoutID] as? String,
                  let workoutID = UUID(uuidString: workoutIDString)
            else { return nil }

            return SharedWorkoutSummary(
                id: record.recordID.recordName,
                ownerRecordName: record[WorkoutKey.ownerID] as? String ?? ownerRecordName,
                workoutID: workoutID,
                name: record[WorkoutKey.name] as? String ?? "Untitled",
                sectionCount: (record[WorkoutKey.sectionCount] as? Int) ?? 0,
                summary: record[WorkoutKey.summary] as? String ?? "",
                updatedAt: record[WorkoutKey.updatedAt] as? Date ?? .distantPast
            )
        }
    }

    /// Fetches and decodes one workout's payload.
    static func download(_ summary: SharedWorkoutSummary) async throws -> SharedWorkoutBundle {
        guard NetworkReachability.shared.isOnline else { throw SharingError.offline }

        let record = try await database.record(for: CKRecord.ID(recordName: summary.id))
        guard let asset = record[WorkoutKey.payload] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url)
        else {
            throw SharingError.payloadUnreadable("the shared data is missing.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: SharedWorkoutPayload
        do {
            payload = try decoder.decode(SharedWorkoutPayload.self, from: data)
        } catch {
            throw SharingError.payloadUnreadable(error.localizedDescription)
        }

        guard payload.formatVersion <= SharedWorkoutPayload.currentVersion else {
            throw SharingError.unsupportedVersion(
                found: payload.formatVersion,
                supported: SharedWorkoutPayload.currentVersion
            )
        }

        // Absent for a v1 record, and for any workout whose exercises have no generated
        // photos — neither is an error, so a failure to read them costs the pictures and
        // not the workout.
        let images = (record[WorkoutKey.images] as? CKAsset).map(unzipImages) ?? [:]
        return SharedWorkoutBundle(
            payload: payload,
            images: images,
            ownerRecordName: summary.ownerRecordName,
            sourceUpdatedAt: summary.updatedAt
        )
    }

    /// Reads the photo zip into memory, keyed by filename.
    ///
    /// Deliberately total: a corrupt or unreadable image asset returns nothing rather
    /// than throwing, because a workout that arrives without its pictures is still a
    /// workout, and refusing the whole download over them would be the wrong trade.
    private static func unzipImages(_ asset: CKAsset) -> [String: Data] {
        guard let url = asset.fileURL else { return [:] }

        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("share-images-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: url, to: staging)
        } catch {
            return [:]
        }

        let names = (try? fileManager.contentsOfDirectory(atPath: staging.path)) ?? []
        var images: [String: Data] = [:]
        for name in names {
            guard let data = try? Data(contentsOf: staging.appendingPathComponent(name)) else { continue }
            images[name] = data
        }
        return images
    }

    // MARK: - Helpers

    /// The user's `Profile` record id.
    ///
    /// **Must not be the bare user record name.** CloudKit already owns a record with
    /// that name — the built-in `Users` record it creates for every account — so saving a
    /// `Profile` under it is an attempt to change an existing record's type, which the
    /// server rejects outright ("invalid attempt to update record from type 'Users'").
    /// Prefixing keeps the id deterministic while landing in unused namespace.
    private static func profileRecordID(for userRecordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: profilePrefix + userRecordName)
    }

    /// The inverse of `profileRecordID` — a looked-up profile has to yield the user
    /// record name, because that (not the profile id) is what `SharedWorkout.ownerID`
    /// stores and what browsing queries by.
    private static func userRecordName(fromProfileID recordName: String) -> String {
        recordName.hasPrefix(profilePrefix)
            ? String(recordName.dropFirst(profilePrefix.count))
            : recordName
    }

    private static let profilePrefix = "profile_"

    /// Deterministic, so republishing overwrites rather than duplicating.
    private static func sharedRecordName(owner: String, workoutID: UUID) -> String {
        "sw_\(owner)_\(workoutID.uuidString)"
    }

    /// Deterministic for the same reason: one record per (follower, followee) pair, so
    /// re-following overwrites instead of accumulating.
    private static func followRecordName(follower: String, followee: String) -> String {
        "follow_\(follower)_\(followee)"
    }

    private static func summarize(_ payload: SharedWorkoutPayload) -> String {
        let sections = payload.workout.sections.filter { $0.deletedAt == nil }
        let types = Set(sections.map(\.sectionTypeRaw)).sorted()
        let exerciseCount = payload.exercises.count
        var parts: [String] = []
        if !types.isEmpty { parts.append(types.map { $0.capitalized }.joined(separator: " · ")) }
        parts.append("\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
