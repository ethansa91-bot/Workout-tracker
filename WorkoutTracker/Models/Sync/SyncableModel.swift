import Foundation
import SwiftData

/// Shared shape for every entity that syncs via CloudKit. `id` is a client-generated
/// UUID (SwiftData's own `persistentModelID` isn't stable across devices/reinstalls,
/// so it can't be the sync key).
protocol SyncableModel: PersistentModel {
    var id: UUID { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

/// Entities whose sibling rows have an explicit display order (workout sections, steps
/// within a section, exercises within a section). Lets reorder/clone logic be written
/// once generically instead of once per entity.
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
    /// Call at the end of any mutation, for anything that cares when a row last changed.
    func markDirty() {
        updatedAt = .now
    }
}

enum SyncDeletion {
    /// Always a soft delete (tombstone) — CloudKit sync needs the deletion itself to
    /// propagate to other devices, which a local hard delete alone can't do.
    static func delete<T: SyncableModel>(_ model: T, context: ModelContext) {
        model.deletedAt = .now
        model.markDirty()
    }
}
