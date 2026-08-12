import Foundation

/// Global sync watermark — a single "everything before this instant has been
/// reconciled" timestamp is simpler than tracking one per table, and cheap: an
/// unaffected table's pull query just returns zero rows.
enum SyncState {
    private static let lastSyncedAtKey = "sync.lastSyncedAt"

    static var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncedAtKey) }
    }
}
