import Foundation
import SwiftData

/// A user-created label on a workout or a section template — "push", "travel", "10 min".
///
/// Purely organisational: nothing here reaches the runner, which is exactly why tags stay
/// editable on a locked workout. The lock protects what a past session *meant*, and a
/// label doesn't change that — the same reasoning `WorkoutEditingService.rename` already
/// carries.
///
/// Structurally a twin of `ExecutionType`: a name-only catalog row in a many-to-many, with
/// the `@Relationship(inverse:)` annotations living on the owning side and plain matching
/// properties here.
@Model
final class WorkoutTag: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    /// Every tag is user-made today; the flag exists so a future seeded set can be told
    /// apart, matching `ExecutionType` and `Equipment`.
    var isCustom: Bool = true
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var workoutsStorage: [Workout]?
    var workouts: [Workout] {
        get { workoutsStorage ?? [] }
        set { workoutsStorage = newValue }
    }

    /// Only ever template sections in practice — the tag UI isn't offered on a section
    /// inside a workout, which carries its parent's tags instead.
    var sectionsStorage: [WorkoutSection]?
    var sections: [WorkoutSection] {
        get { sectionsStorage ?? [] }
        set { sectionsStorage = newValue }
    }

    init(id: UUID = UUID(), name: String, isCustom: Bool = true) {
        self.id = id
        self.name = name
        self.isCustom = isCustom
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
