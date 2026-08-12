import Foundation
import SwiftData

/// Shared shape for every entity that participates in Supabase sync. `id` is a
/// client-generated UUID (SwiftData's own `persistentModelID` isn't stable across
/// devices/reinstalls, so it can't be the sync key).
protocol SyncableModel: PersistentModel {
    var id: UUID { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var isDirty: Bool { get set }
    var remoteSyncedAt: Date? { get set }
}

/// Entities whose sibling rows have an explicit display order (workout blocks, steps
/// within a block, exercises within a block). Lets reorder/clone logic be written once
/// generically instead of once per entity.
protocol Orderable: AnyObject {
    var sortOrder: Int { get set }
}

extension Orderable where Self: SyncableModel {
    /// Assigns 0...n-1 to `items` in the order given, marking only the ones whose
    /// position actually changed. Used after any insert/delete/move/clone so sibling
    /// rows never end up with gaps or duplicate positions.
    static func resequence(_ items: [Self]) {
        for (index, item) in items.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.markDirty()
        }
    }
}

extension SyncableModel {
    /// Call at the end of any mutation so the next sync knows to push this row.
    func markDirty() {
        updatedAt = .now
        isDirty = true
    }
}

enum SyncDeletion {
    /// A record never pushed to Supabase can simply be removed. One that was pushed at
    /// least once must be tombstoned (soft-deleted) instead, so the deletion can still
    /// propagate to Supabase on the next sync.
    static func delete<T: SyncableModel>(_ model: T, context: ModelContext) {
        if model.remoteSyncedAt == nil {
            context.delete(model)
        } else {
            model.deletedAt = .now
            model.markDirty()
        }
    }
}
