import CloudKit
import Foundation
import SwiftData

/// Answers "why isn't sharing working?" with the actual reason.
///
/// Sharing has three failure modes that all look identical from the outside — no
/// followers ever appear — and only one of them is a bug:
///
/// 1. **A field isn't marked queryable.** `followerRecordNames()` queries `Follow` by
///    `followeeID`, and CloudKit rejects any query on a field with no queryable index.
///    Auto-created record types get none, so this fails until someone adds it in the
///    Console by hand.
/// 2. **The record type was never deployed to Production.** Development and Production
///    are separate schemas; a debug build writes one and a TestFlight build reads the
///    other.
/// 3. **The two devices aren't on the same environment**, which produces symptoms
///    indistinguishable from either of the above.
///
/// Each step reports the raw `CKError` rather than a friendly summary, because the whole
/// point is to name the field and the code precisely enough to act on.
@MainActor
enum SharingSetupCheck {

    struct Step: Identifiable {
        let id = UUID()
        let title: String
        let outcome: Outcome

        enum Outcome {
            case ok(String)
            case info(String)
            case failed(String, fix: String?)
        }

        var isFailure: Bool {
            if case .failed = outcome { return true }
            return false
        }
    }

    static func run(context: ModelContext) async -> [Step] {
        var steps: [Step] = []

        // 1 — account. Everything else is meaningless without one.
        let container = CKContainer(identifier: CloudKitContainer.identifier)
        do {
            let status = try await container.accountStatus()
            if status == .available {
                steps.append(Step(title: "iCloud account", outcome: .ok("Signed in")))
            } else {
                steps.append(Step(
                    title: "iCloud account",
                    outcome: .failed(
                        describe(status),
                        fix: "Sign in to iCloud in the Settings app. Sharing identifies people by their iCloud account."
                    )
                ))
                return steps
            }
        } catch {
            steps.append(Step(title: "iCloud account", outcome: .failed(raw(error), fix: nil)))
            return steps
        }

        // 2 — environment. Not pass/fail on its own, but a mismatch between two devices
        // explains every other symptom here, and nothing else in the app reports it.
        steps.append(Step(
            title: "CloudKit environment",
            outcome: .info(
                CloudKitEnvironment.current.rawValue
                + (CloudKitEnvironment.isExplicitlyPinned ? " (pinned)" : "")
                + " — both people must be on builds using the same one."
            )
        ))

        // 3 — profile. Proves the Profile type exists and is writable, and that the
        // shareCode index works, since following anyone at all goes through that query.
        do {
            let profile = try await SharingService.ensureProfile()
            steps.append(Step(
                title: "Your profile",
                outcome: .ok("Code \(ShareCode.format(profile.shareCode))")
            ))
        } catch {
            steps.append(Step(
                title: "Your profile",
                outcome: .failed(raw(error), fix: fixHint(for: error, recordType: "Profile", field: "shareCode"))
            ))
        }

        // 4 — the query automatic follow-back depends on, and the step that was
        // previously capable of passing while the whole feature was unconfigured.
        do {
            switch try await SharingService.followerRecordNames() {
            case .followers(let followers):
                steps.append(Step(
                    title: "Follow-back check",
                    outcome: .ok(followers.isEmpty
                        ? "Working — nobody is following you yet"
                        : "Working — \(followers.count) follower\(followers.count == 1 ? "" : "s")")
                ))

            case .typeMissing:
                // Not "no followers". The type has never been written, so follow-back
                // cannot work and the Console has nothing to index yet. Create it here,
                // because nothing else will.
                steps.append(await probeStep())
            }
        } catch {
            steps.append(Step(
                title: "Follow-back check",
                outcome: .failed(raw(error), fix: fixHint(for: error, recordType: "Follow", field: "followeeID"))
            ))
        }

        // 5 — repair, so a check is also a fix for the commonest recoverable case: a
        // follow record lost to an earlier failure.
        await FollowService.reassertFollowRecords(context: context)
        let followedCount = ((try? context.fetch(FetchDescriptor<FollowedUser>())) ?? [])
            .filter { $0.deletedAt == nil }.count
        steps.append(Step(
            title: "Your follows",
            outcome: .ok(followedCount == 0
                ? "Not following anyone"
                : "Re-announced \(followedCount) follow\(followedCount == 1 ? "" : "s")")
        ))

        return steps
    }

    /// Creates the `Follow` record type, and reports what to do next.
    ///
    /// Split out because the outcome isn't pass/fail: writing the type is progress, but
    /// the user still has to add the index by hand before follow-back works, and the
    /// check has to say so in the right order.
    private static func probeStep() async -> Step {
        do {
            try await SharingService.createFollowSchemaProbe()
            return Step(
                title: "Follow record type",
                outcome: .failed(
                    "Didn't exist — just created it. Follow-back can't work until it's indexed.",
                    fix: consoleSteps
                )
            )
        } catch {
            return Step(
                title: "Follow record type",
                outcome: .failed(
                    "Doesn't exist, and couldn't be created — \(raw(error))",
                    fix: (error as? CKError)?.code == .permissionFailure || CloudKitEnvironment.current == .production
                        ? "Production schemas can't be changed from the app. Create and index the type in Development first, then Deploy Schema Changes to Production."
                        : fixHint(for: error, recordType: "Follow", field: "followeeID")
                )
            )
        }
    }

    /// The ordering matters and is easy to get backwards — an index can't be added to a
    /// record type that doesn't exist yet.
    static let consoleSteps = """
        In CloudKit Console, with the environment set to DEVELOPMENT (Follow never \
        appears under Production until deployed):
        1. Reload — Follow now appears under Record Types.
        2. Schema → Indexes → Follow → add QUERYABLE on followeeID (required), \
        and on recordName (harmless, and CloudKit wants it for some queries).
        3. Run this check again — the Follow step should read OK.
        4. Only then: Deploy Schema Changes → Production.
        """

    /// One line per step, for the clipboard — the same idea as
    /// `SyncDiagnosticsView.copyDiagnostics`.
    static func transcript(_ steps: [Step]) -> String {
        var lines = [
            "Sharing setup check",
            "container: \(CloudKitContainer.identifier)",
            "environment: \(CloudKitEnvironment.current.rawValue)",
            "",
        ]
        for step in steps {
            switch step.outcome {
            case .ok(let detail): lines.append("OK   \(step.title): \(detail)")
            case .info(let detail): lines.append("--   \(step.title): \(detail)")
            case .failed(let detail, let fix):
                lines.append("FAIL \(step.title): \(detail)")
                if let fix {
                    for line in fix.components(separatedBy: "\n") {
                        lines.append("     fix: \(line)")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Error reading

    /// The raw code and message. Deliberately not `CloudKitErrorFormatter.describe`,
    /// which is tuned for reassuring a user — here the exact wording is the payload,
    /// because it names the field CloudKit is complaining about.
    private static func raw(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return (error as? SharingError)?.errorDescription ?? error.localizedDescription
        }
        return "CKError \(ckError.errorCode) — \(ckError.localizedDescription)"
    }

    /// Turns the two errors that actually happen here into the Console steps that fix
    /// them. Anything else falls through to no hint rather than a guess.
    private static func fixHint(for error: Error, recordType: String, field: String) -> String? {
        guard let ckError = error as? CKError else { return nil }
        switch ckError.code {
        case .invalidArguments:
            return "\(recordType).\(field) needs a QUERYABLE index — CloudKit refuses any query on an unindexed field.\n" + consoleSteps
        case .unknownItem:
            return "The \(recordType) record type doesn't exist in the \(CloudKitEnvironment.current.rawValue) environment yet. A custom type is created by the first successful save in Development, and can only be indexed once it exists.\n" + consoleSteps
        case .notAuthenticated:
            return "Sign in to iCloud in the Settings app."
        case .networkUnavailable, .networkFailure:
            return "No connection — this check needs the network."
        default:
            return nil
        }
    }

    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "Signed in"
        case .noAccount: return "No iCloud account on this device"
        case .restricted: return "iCloud is restricted on this device"
        case .couldNotDetermine: return "Couldn't determine account status"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        @unknown default: return "Unknown account status"
        }
    }
}
