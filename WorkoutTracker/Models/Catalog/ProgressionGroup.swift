import Foundation
import SwiftData

/// One ladder of exercises, ordered by level: inverted row → band-assisted pull-up →
/// pull-up → weighted pull-up.
///
/// A join model rather than an exercise-to-exercise relationship, for two reasons. A
/// self-referential many-to-many has no "other side" to hang the bare inverse property on,
/// which is how every other pairing in this app satisfies CloudKit's inverse rule. And the
/// level has to live somewhere: putting it on `ProgressionStep` is what lets two exercises
/// share a level and read as alternatives rather than as a strict sequence.
///
/// Because the ladder is a shared object rather than a list owned by one exercise, every
/// member sees the whole thing — walk `Exercise.progressionSteps → group → sortedSteps`
/// from any rung.
@Model
final class ProgressionGroup: SyncableModel {
    var id: UUID = UUID()
    /// The highest level ever logged on this ladder. Rises when a set is logged at a rung
    /// above it and never falls — doing an easier version is not losing a level, which is
    /// the same rule a personal record follows.
    ///
    /// User progress stored on a catalog model, as `Exercise.isFavorited` already is.
    var reachedLevel: Int = 1
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// Cascades: a deleted ladder's rungs have nothing left to belong to. Optional at the
    /// type level because CloudKit requires it of every to-many relationship.
    @Relationship(deleteRule: .cascade, inverse: \ProgressionStep.group)
    var stepsStorage: [ProgressionStep]?
    var steps: [ProgressionStep] {
        get { stepsStorage ?? [] }
        set { stepsStorage = newValue }
    }

    init(id: UUID = UUID(), reachedLevel: Int = 1) {
        self.id = id
        self.reachedLevel = reachedLevel
        self.updatedAt = .now
        self.deletedAt = nil
    }

    /// Live rungs, easiest first. Ties broken by name so two exercises sharing a level
    /// keep a stable order rather than shuffling between renders.
    var sortedSteps: [ProgressionStep] {
        steps
            // Same optional-chaining trap `Exercise.progressionStep` had: a rung with no
            // exercise passed `$0.exercise?.deletedAt == nil`, then padded `maxLevel` and
            // the `count > 1` gate that decides whether a ladder is offered at all.
            .filter {
                guard $0.deletedAt == nil, let exercise = $0.exercise else { return false }
                return exercise.deletedAt == nil
            }
            .sorted { lhs, rhs in
                lhs.level == rhs.level
                    ? (lhs.exercise?.displayName ?? "") < (rhs.exercise?.displayName ?? "")
                    : lhs.level < rhs.level
            }
    }

    var maxLevel: Int {
        sortedSteps.map(\.level).max() ?? 1
    }

    /// The rungs to start from, given what has been reached. Several when they share a
    /// level — the caller picks, since at that point they are alternatives and nothing
    /// here can say which one the user meant.
    func steps(atLevel level: Int) -> [ProgressionStep] {
        sortedSteps.filter { $0.level == level }
    }
}
