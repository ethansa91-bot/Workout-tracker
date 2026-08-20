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
    }

    private(set) var lastImport: Event?
    private(set) var lastExport: Event?
    private(set) var lastSetup: Event?

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
        let record = Event(date: endDate, succeeded: event.succeeded, error: event.error)

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
