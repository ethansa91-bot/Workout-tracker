import Foundation
import SwiftData

/// What a download would do to the recipient's progressions.
///
/// Deliberately **not** a `CatalogDecision`. That machinery matches on name, and a
/// `ProgressionGroup` has no name and a random UUID — two people's ladders for the same
/// three exercises never share an id, so id matching finds nothing and name matching has
/// nothing to compare. Ladders are matched structurally instead: by which exercises they
/// contain, once those exercises have been resolved to local rows.
struct ProgressionDecision: Identifiable {
    /// What the user chose to do with one incoming ladder.
    enum Resolution: Equatable {
        /// Take theirs. Any local ladder holding one of these exercises is dismantled
        /// first — an exercise on two ladders is the state every accessor breaks on.
        case useTheirs
        /// Leave the recipient's library exactly as it is.
        case keepMine
        /// Import their ladder without the exercises already on one of the recipient's.
        case nonConflictingOnly
    }

    /// The publisher's group id.
    let incomingID: UUID
    /// Their rungs, easiest first: level and the exercise name as it will read locally.
    let incomingRungs: [Rung]
    /// The recipient's ladders that already claim one of those exercises.
    let conflicts: [LocalLadder]
    /// Exercises this ladder would add that the workout itself never uses.
    let addedExerciseNames: [String]
    var resolution: Resolution

    var id: UUID { incomingID }

    var hasConflict: Bool { !conflicts.isEmpty }

    struct Rung: Identifiable {
        let id: UUID
        let level: Int
        let name: String
        /// True when this rung's exercise is already on one of the recipient's ladders.
        let clashes: Bool
    }

    struct LocalLadder: Identifiable {
        let id: UUID
        let rungs: [Rung]
    }
}

/// Everything the progression half of a download implies.
struct ProgressionImportPlan {
    var decisions: [ProgressionDecision] = []

    var isEmpty: Bool { decisions.isEmpty }

    /// Whether anything here would actually change the library, given the choices so far.
    var changesAnything: Bool {
        decisions.contains { $0.resolution != .keepMine }
    }

    var conflictCount: Int { decisions.count(where: { $0.hasConflict }) }
}

private extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
