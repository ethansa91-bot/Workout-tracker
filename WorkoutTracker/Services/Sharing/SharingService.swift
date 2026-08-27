import CloudKit
import Foundation

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
    }

    private enum ProfileKey {
        static let shareCode = "shareCode"
        static let displayName = "displayName"
        static let updatedAt = "updatedAt"
    }

    private enum WorkoutKey {
        static let ownerID = "ownerID"
        static let workoutID = "workoutID"
        static let name = "name"
        static let sectionCount = "sectionCount"
        static let summary = "summary"
        static let payload = "payload"
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
            return profile
        }

        let record = CKRecord(recordType: RecordType.profile, recordID: recordID)
        let code = ShareCode.generate()
        record[ProfileKey.shareCode] = ShareCode.normalize(code)
        record[ProfileKey.displayName] = ""
        record[ProfileKey.updatedAt] = Date()

        let saved = try await database.save(record)
        let stored = saved[ProfileKey.shareCode] as? String ?? code
        AppSettings.shareCode = stored
        return SharedProfile(recordName: recordName, shareCode: stored, displayName: "")
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
        AppSettings.shareCode = code
        return SharedProfile(
            recordName: recordName,
            shareCode: code,
            displayName: saved[ProfileKey.displayName] as? String ?? ""
        )
    }

    static func setDisplayName(_ name: String) async throws {
        let recordName = try await myRecordName()
        let recordID = profileRecordID(for: recordName)
        guard let record = try? await database.record(for: recordID) else { return }
        record[ProfileKey.displayName] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record[ProfileKey.updatedAt] = Date()
        _ = try await database.save(record)
    }

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
    static func publish(_ payload: SharedWorkoutPayload) async throws {
        let recordName = try await myRecordName()
        let recordID = CKRecord.ID(recordName: sharedRecordName(owner: recordName, workoutID: payload.workout.id))
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: RecordType.sharedWorkout, recordID: recordID)

        let encoder = JSONEncoder()
        // Matching the archive services, so shared payloads and archives stay comparable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        // A CKAsset rather than a field: CKRecord fields cap around 1MB, and a workout
        // plus its exercise manifest can approach that.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let sections = payload.workout.sections.filter { $0.deletedAt == nil }
        record[WorkoutKey.ownerID] = recordName
        record[WorkoutKey.workoutID] = payload.workout.id.uuidString
        record[WorkoutKey.name] = payload.workout.name
        record[WorkoutKey.sectionCount] = sections.count as NSNumber
        record[WorkoutKey.summary] = summarize(payload)
        record[WorkoutKey.payload] = CKAsset(fileURL: url)
        record[WorkoutKey.updatedAt] = Date()

        _ = try await database.save(record)
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
    static func download(_ summary: SharedWorkoutSummary) async throws -> SharedWorkoutPayload {
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
        return payload
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
