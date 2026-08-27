import Foundation
import CoreData
import Observation

/// Observes the CloudKit mirroring events SwiftData publishes under the hood, so the
/// app can report what sync is actually doing. `NSPersistentCloudKitContainer` posts
/// `eventChangedNotification` for every setup/import/export, both when it starts and
/// when it finishes; only finished events (`endDate != nil`) are recorded here.
///
/// Two consumers share this one subscription: `SyncDiagnosticsView`, which displays the
/// timestamps, and `CatalogReconciliation`, which waits for the first successful import
/// before de-duplicating the seeded catalog.
@Observable
@MainActor
final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    struct Event {
        let date: Date
        let succeeded: Bool
        let error: Error?
        /// Rendered at receipt time, not at display time. `CKError.partialFailure`
        /// carries its real cause in `partialErrorsByItemID`, which lives in the bridged
        /// `NSError`'s `userInfo` — read minutes later from a retained `Error`
        /// existential, the code survives but that payload can come back empty, which
        /// is exactly how a failure reduces to an unactionable "partialFailure (2)".
        let detail: String?
    }

    private(set) var lastImport: Event?
    private(set) var lastExport: Event?
    private(set) var lastSetup: Event?

    /// Every failure seen this launch, newest first. A single `lastExport` is not enough
    /// to debug with: CloudKit retries, and a later generic failure overwrites the
    /// specific one that named the cause. Capped so a retry loop can't grow it without
    /// bound.
    private(set) var failures: [(type: String, event: Event)] = []
    private static let maxFailures = 20

    /// Fires once per successful import. `CatalogReconciliation` uses this rather than
    /// polling, so dedupe runs exactly when there is something new to reconcile.
    var onImportCompleted: (() -> Void)?

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey],
                  let event = raw as? NSPersistentCloudKitContainer.Event
            else { return }
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        // Events are posted twice — once at start, once at completion. Only the
        // completed ones carry a meaningful success/failure result.
        guard let endDate = event.endDate else { return }
        // Format here, while still inside the notification callback and the error's
        // userInfo is intact — see `Event.detail`.
        let detail = event.error.map(CloudKitErrorFormatter.describe)
        if let detail {
            print("CloudKit \(event.type) failed:\n\(detail)")
        }
        let record = Event(date: endDate, succeeded: event.succeeded, error: event.error, detail: detail)

        if !event.succeeded {
            failures.insert((type: String(describing: event.type), event: record), at: 0)
            if failures.count > Self.maxFailures { failures.removeLast() }
        }

        switch event.type {
        case .setup:
            lastSetup = record
        case .import:
            lastImport = record
            if event.succeeded { onImportCompleted?() }
        case .export:
            lastExport = record
        @unknown default:
            break
        }
    }
}
