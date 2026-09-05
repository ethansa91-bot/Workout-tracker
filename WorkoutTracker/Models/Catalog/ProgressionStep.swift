import Foundation
import SwiftData

/// One rung: an exercise's place on a `ProgressionGroup`'s ladder.
///
/// Levels are not unique within a group. Two exercises at level 2 are alternatives at the
/// same difficulty — a band-assisted and a leg-assisted pull-up — and the ladder is walked
/// by level, not by position.
@Model
final class ProgressionStep: SyncableModel {
    var id: UUID = UUID()
    var group: ProgressionGroup?
    var exercise: Exercise?
    /// 1-based. Nothing enforces contiguity: deleting the only level-3 rung leaves 1, 2, 4
    /// standing, which still reads correctly as a ladder.
    var level: Int = 1
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        group: ProgressionGroup? = nil,
        exercise: Exercise? = nil,
        level: Int = 1
    ) {
        self.id = id
        self.group = group
        self.exercise = exercise
        self.level = level
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
