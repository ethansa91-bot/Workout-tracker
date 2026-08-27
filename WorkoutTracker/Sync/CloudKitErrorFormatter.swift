import CloudKit
import Foundation

/// Turns a CloudKit mirroring error into something a person can act on.
///
/// `localizedDescription` alone is close to useless for the failures that actually
/// happen here — a schema that was never deployed to Production surfaces as a generic
/// "Request failed", with the record type buried in a partial-failure sub-error. This
/// unwraps that structure and names the specific cause, because the alternative is a
/// bare "(failed)" that gives a user nothing to search for.
///
/// Two shapes matter and neither is the obvious one:
/// - `partialFailure` (code 2) is a *wrapper*. Its own description says nothing; the
///   cause is entirely inside `partialErrorsByItemID`.
/// - SwiftData mirroring errors frequently arrive as `NSCocoaErrorDomain` with the real
///   `CKError` hidden under `NSUnderlyingErrorKey`, so a plain `as? CKError` cast misses
///   them completely.
enum CloudKitErrorFormatter {

    /// One-line summary plus, where CloudKit gives us one, a concrete next step.
    static func describe(_ error: Error) -> String {
        guard let ckError = resolveCloudKitError(error) else {
            // Not CloudKit at all (or too deeply wrapped to find). Still name the
            // domain and code — an unrecognized wrapper should stay identifiable
            // rather than collapsing to a bare sentence.
            let nsError = error as NSError
            var parts = ["\(nsError.domain) \(nsError.code)"]
            if !nsError.localizedDescription.isEmpty {
                parts.append(nsError.localizedDescription)
            }
            return parts.joined(separator: "\n")
        }

        var parts: [String] = ["\(codeName(ckError.code)) (\(ckError.errorCode))"]

        let description = ckError.localizedDescription
        if !description.isEmpty {
            parts.append(description)
        }

        // The record-type name for an undeployed schema lives here, not in the
        // top-level description, so this is the part worth digging out.
        parts.append(contentsOf: partialFailureDetail(ckError))

        if let advice = advice(for: ckError.code) {
            parts.append(advice)
        }

        return parts.joined(separator: "\n")
    }

    /// Finds the real `CKError` inside whatever wrapped it. Core Data batch saves nest
    /// the useful error one or two levels down, and a failed unwrap here is the
    /// difference between naming the cause and printing boilerplate.
    private static func resolveCloudKitError(_ error: Error, depth: Int = 0) -> CKError? {
        if let ckError = error as? CKError { return ckError }
        guard depth < 4 else { return nil }

        let nsError = error as NSError
        if nsError.domain == CKErrorDomain {
            return CKError(_nsError: nsError)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           let found = resolveCloudKitError(underlying, depth: depth + 1) {
            return found
        }
        // Batch Core Data saves report every failed row here rather than in
        // NSUnderlyingErrorKey, so a single-error unwrap would miss all of them.
        if let multiple = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [Error] {
            for candidate in multiple {
                if let found = resolveCloudKitError(candidate, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// Sub-error lines for a `.partialFailure`, or an explicit note when CloudKit gave
    /// us the wrapper with nothing inside it — silence there is what makes a bare
    /// "CKErrorDomain 2" impossible to act on.
    private static func partialFailureDetail(_ ckError: CKError) -> [String] {
        guard ckError.code == .partialFailure else { return [] }

        // Read the raw userInfo rather than the typed `partialErrorsByItemID`, which is
        // generic over `CKRecord.ID` and returns nil for a ZONE-level partial failure —
        // where the keys are `CKRecordZone.ID`. That silent nil is how a real, populated
        // error dictionary reduces to "listed no per-record errors".
        let raw = (ckError as NSError).userInfo[CKPartialErrorsByItemIDKey]
        let byItem: [AnyHashable: Any]
        if let typed = ckError.partialErrorsByItemID, !typed.isEmpty {
            byItem = typed.reduce(into: [:]) { $0[$1.key] = $1.value }
        } else if let dictionary = raw as? [AnyHashable: Any], !dictionary.isEmpty {
            byItem = dictionary
        } else {
            var lines = [
                "CloudKit reported a partial failure but listed no per-record errors.",
                "The per-record reasons are redacted from the public error. Open Console.app, connect this device, and filter on \"CD_\" to see the server message — it names the record type and field.",
            ]
            // Dump whatever userInfo does carry — with no sub-errors this is the only
            // remaining evidence, and it is what turns a dead end into a lead.
            let userInfo = (ckError as NSError).userInfo
            for (key, value) in userInfo.sorted(by: { "\($0.key)" < "\($1.key)" })
            where key != NSUnderlyingErrorKey && key != NSLocalizedDescriptionKey {
                lines.append("\(key) = \(value)")
            }
            if let underlying = userInfo[NSUnderlyingErrorKey] as? NSError {
                lines.append("underlying: \(underlying.domain) \(underlying.code) — \(underlying.localizedDescription)")
                for (key, value) in underlying.userInfo.sorted(by: { "\($0.key)" < "\($1.key)" })
                where key != NSUnderlyingErrorKey {
                    lines.append("  \(key) = \(value)")
                }
            }
            return lines
        }

        // A failed export usually repeats the same message once per record, so
        // deduplicate and cap — three distinct causes is plenty to diagnose from.
        var seen: Set<String> = []
        var messages: [String] = []
        for value in byItem.values {
            guard let underlying = value as? Error else { continue }
            let line = describeSubError(underlying)
            guard !line.isEmpty, seen.insert(line).inserted else { continue }
            messages.append(line)
            if messages.count == 3 { break }
        }

        if messages.isEmpty {
            return ["CloudKit listed \(byItem.count) failed record\(byItem.count == 1 ? "" : "s") but gave no reason for any of them."]
        }

        let remaining = byItem.count - messages.count
        if remaining > 0 {
            messages.append("…and \(remaining) more record\(remaining == 1 ? "" : "s").")
        }
        return messages
    }

    /// One sub-error, with its own code and failure reason. The code matters as much as
    /// the message: `unknownItem`/`invalidArguments` on an export is the signature of a
    /// schema that isn't in this environment, and the record type usually appears only
    /// in the failure reason.
    private static func describeSubError(_ error: Error) -> String {
        let nsError = error as NSError
        var pieces: [String] = []

        if let ckError = resolveCloudKitError(error) {
            pieces.append("\(codeName(ckError.code)) (\(ckError.errorCode))")
        } else {
            pieces.append("\(nsError.domain) \(nsError.code)")
        }

        let description = nsError.localizedDescription
        if !description.isEmpty {
            pieces.append(description)
        }
        // Where CloudKit names the offending record type, it's here rather than in the
        // description.
        if let reason = nsError.localizedFailureReason, !reason.isEmpty, reason != description {
            pieces.append(reason)
        }
        if let serverMessage = nsError.userInfo["ServerErrorDescription"] as? String,
           !serverMessage.isEmpty, serverMessage != description {
            pieces.append(serverMessage)
        }

        return "• " + pieces.joined(separator: " — ")
    }

    /// Only for the codes where the fix isn't guessable from the message itself.
    private static func advice(for code: CKError.Code) -> String? {
        switch code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings and make sure iCloud Drive is on."
        case .quotaExceeded:
            return "This Apple Account is out of iCloud storage."
        case .networkUnavailable, .networkFailure:
            return "This usually resolves once the connection is back."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is throttling or temporarily down — it should retry on its own."
        case .managedAccountRestricted:
            return "iCloud is restricted by a device management profile."
        case .incompatibleVersion:
            return "This app version is too old for the data in iCloud."
        case .partialFailure:
            // The overwhelmingly common cause of a contentless partialFailure on export:
            // a field exists in the app's model but not in the CloudKit environment the
            // build is pointed at. Production schemas are frozen — new fields have to be
            // deployed from the Console before a build using them can export.
            return "A field in the app may be missing from the CloudKit environment this build targets. If this is a release build, deploy the schema to Production from the CloudKit Console."
        case .permissionFailure, .unknownItem:
            return "If this is a TestFlight or App Store build, the CloudKit schema may not be deployed to Production. Deploy it from the CloudKit Console."
        case .invalidArguments:
            // Left without advice on purpose. The server message carries the real cause
            // — a record-type mismatch, an unqueryable field, a bad predicate — and it is
            // always more specific than anything guessable from the code alone. Asserting
            // "deploy your schema" here has already sent one debugging session down the
            // wrong path.
            return nil
        default:
            return nil
        }
    }

    private static func codeName(_ code: CKError.Code) -> String {
        switch code {
        case .internalError: return "internalError"
        case .partialFailure: return "partialFailure"
        case .networkUnavailable: return "networkUnavailable"
        case .networkFailure: return "networkFailure"
        case .badContainer: return "badContainer"
        case .serviceUnavailable: return "serviceUnavailable"
        case .requestRateLimited: return "requestRateLimited"
        case .missingEntitlement: return "missingEntitlement"
        case .notAuthenticated: return "notAuthenticated"
        case .permissionFailure: return "permissionFailure"
        case .unknownItem: return "unknownItem"
        case .invalidArguments: return "invalidArguments"
        case .resultsTruncated: return "resultsTruncated"
        case .serverRecordChanged: return "serverRecordChanged"
        case .serverRejectedRequest: return "serverRejectedRequest"
        case .assetFileNotFound: return "assetFileNotFound"
        case .assetFileModified: return "assetFileModified"
        case .incompatibleVersion: return "incompatibleVersion"
        case .constraintViolation: return "constraintViolation"
        case .operationCancelled: return "operationCancelled"
        case .changeTokenExpired: return "changeTokenExpired"
        case .batchRequestFailed: return "batchRequestFailed"
        case .zoneBusy: return "zoneBusy"
        case .badDatabase: return "badDatabase"
        case .quotaExceeded: return "quotaExceeded"
        case .zoneNotFound: return "zoneNotFound"
        case .limitExceeded: return "limitExceeded"
        case .userDeletedZone: return "userDeletedZone"
        case .tooManyParticipants: return "tooManyParticipants"
        case .alreadyShared: return "alreadyShared"
        case .referenceViolation: return "referenceViolation"
        case .managedAccountRestricted: return "managedAccountRestricted"
        case .participantMayNeedVerification: return "participantMayNeedVerification"
        case .serverResponseLost: return "serverResponseLost"
        case .assetNotAvailable: return "assetNotAvailable"
        case .accountTemporarilyUnavailable: return "accountTemporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }
}
