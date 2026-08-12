import Foundation
import SwiftData

enum WorkoutDisplayType: String {
    case empty, time, rep, mixed
}

/// The kind chosen at creation time, which governs how many/which blocks the workout
/// is allowed to hold. Distinct from `displayType` below, which is purely derived
/// from the blocks that happen to exist (for icons/labels) and never restricts
/// anything.
enum WorkoutKind: String, Codable {
    case personalized, byTime, byRep
}

@Model
final class Workout: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var clonedFromWorkoutId: UUID?
    var kindRaw: String = WorkoutKind.personalized.rawValue
    var isArchived: Bool = false
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutBlock.workout)
    var blocks: [WorkoutBlock] = []

    /// Deny, not cascade: a workout with sessions is history and must not be able to
    /// vanish out from under them via a careless local delete.
    @Relationship(deleteRule: .deny, inverse: \WorkoutSession.workout)
    var sessions: [WorkoutSession] = []

    init(id: UUID = UUID(), name: String, notes: String? = nil, clonedFromWorkoutId: UUID? = nil, kind: WorkoutKind = .personalized) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = .now
        self.clonedFromWorkoutId = clonedFromWorkoutId
        self.kindRaw = kind.rawValue
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }

    var kind: WorkoutKind {
        get { WorkoutKind(rawValue: kindRaw) ?? .personalized }
        set { kindRaw = newValue.rawValue }
    }

    /// Locked the instant any session — in-progress, paused, finished, or abandoned —
    /// has ever referenced this workout, since editing afterward would corrupt that
    /// history's meaning. Computed, not stored, so it can never go stale. Use
    /// `WorkoutCloningService` to get an editable copy once locked.
    var isLocked: Bool {
        !sessions.isEmpty
    }

    var sortedBlocks: [WorkoutBlock] {
        blocks
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Derived, not stored: a stored flag would need perfect invalidation on every
    /// block insert/type-change/delete. This is cheap since `blocks` is already what's
    /// rendered.
    var displayType: WorkoutDisplayType {
        let types = Set(sortedBlocks.map(\.blockType))
        if types.isEmpty { return .empty }
        if types == [.time] { return .time }
        if types == [.rep] { return .rep }
        return .mixed
    }
}
