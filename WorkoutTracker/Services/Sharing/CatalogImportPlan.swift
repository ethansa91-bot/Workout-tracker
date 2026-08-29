import Foundation

/// What will happen to one incoming catalog row when the import runs.
///
/// The two destructive-sounding cases aren't: **nothing here ever deletes a local row or
/// inserts a second copy of one that already exists.** `useTheirs` overwrites the fields
/// of the local object in place, which is precisely what keeps every workout, section and
/// logged set that already points at it pointing at it afterwards.
enum CatalogResolution: Equatable {
    /// Matched, and nothing differs. Never shown — there's no decision to make.
    case identical
    /// Matched; keep the local row exactly as it is and just use it.
    case keepMine
    /// Matched; overwrite the local row's fields with theirs, in place.
    case useTheirs
    /// Matched; keep local scalars, union the relationships, adopt theirs only where the
    /// local value is empty.
    case merge
    /// No match — add it to the library.
    case createNew
    /// No match by name, but the user pointed it at an existing local row (their
    /// "Barbell Bench" is my "Bench Press"). Adds nothing; maps and moves on.
    case link(UUID)

    var addsARow: Bool {
        if case .createNew = self { return true }
        return false
    }

    /// Whether applying this writes to the matched local row.
    var mutatesLocal: Bool {
        switch self {
        case .useTheirs, .merge: return true
        case .identical, .keepMine, .createNew, .link: return false
        }
    }
}

/// One field that differs between the local row and the incoming one, rendered
/// side-by-side on the conflict page.
struct CatalogDifference: Identifiable, Equatable {
    let field: String
    let mine: String
    let theirs: String
    var id: String { field }
}

/// One incoming row, what it matched, and what the user has decided to do with it.
struct CatalogDecision<DTO>: Identifiable {
    let incoming: DTO
    /// The publisher's id — the key the workout's references are expressed in.
    let incomingID: UUID
    let incomingName: String
    /// `SyncableModel.id` of the matched local row, if there was one.
    var localID: UUID?
    var localName: String?
    var differences: [CatalogDifference]
    var resolution: CatalogResolution

    var id: UUID { incomingID }

    /// Matched something, and they aren't the same — the case the user is asked about.
    var isConflict: Bool { localID != nil && !differences.isEmpty }
    /// Matched nothing. Defaults to being added, but can be pointed at a local row.
    var isNew: Bool { localID == nil }
}

/// Every decision a download implies, grouped by type.
///
/// Ordered as the import applies them: categories before the things that belong to them,
/// muscles and equipment before the exercises that reference them.
struct CatalogImportPlan {
    var muscleCategories: [CatalogDecision<ArchiveMuscleCategory>] = []
    var muscles: [CatalogDecision<ArchiveMuscle>] = []
    var equipment: [CatalogDecision<ArchiveEquipment>] = []
    var exerciseCategories: [CatalogDecision<ArchiveExerciseCategory>] = []
    var exercises: [CatalogDecision<ArchiveExercise>] = []

    /// Counts across every type, for the review screen's summary and the post-import
    /// confirmation.
    var conflictCount: Int {
        muscleCategories.count(where: \.isConflict)
            + muscles.count(where: \.isConflict)
            + equipment.count(where: \.isConflict)
            + exerciseCategories.count(where: \.isConflict)
            + exercises.count(where: \.isConflict)
    }

    var newCount: Int {
        muscleCategories.count(where: \.isNew)
            + muscles.count(where: \.isNew)
            + equipment.count(where: \.isNew)
            + exerciseCategories.count(where: \.isNew)
            + exercises.count(where: \.isNew)
    }

    var unchangedCount: Int { totalCount - conflictCount - newCount }

    /// How many rows the import will actually create, given the choices made so far.
    /// Distinct from `newCount`, which is structural: linking an unmatched item to an
    /// existing one leaves it "new" but stops it adding anything.
    var willAddCount: Int {
        muscleCategories.count(where: { $0.resolution.addsARow })
            + muscles.count(where: { $0.resolution.addsARow })
            + equipment.count(where: { $0.resolution.addsARow })
            + exerciseCategories.count(where: { $0.resolution.addsARow })
            + exercises.count(where: { $0.resolution.addsARow })
    }

    /// Unmatched rows the user has pointed at something they already have.
    var linkedCount: Int {
        func isLinked<T>(_ decision: CatalogDecision<T>) -> Bool {
            if case .link = decision.resolution { return true }
            return false
        }
        return muscleCategories.count(where: isLinked)
            + muscles.count(where: isLinked)
            + equipment.count(where: isLinked)
            + exerciseCategories.count(where: isLinked)
            + exercises.count(where: isLinked)
    }

    var totalCount: Int {
        muscleCategories.count + muscles.count + equipment.count
            + exerciseCategories.count + exercises.count
    }

    /// Everything matched something identical, so there is genuinely nothing to ask.
    var needsReview: Bool { conflictCount > 0 || newCount > 0 }

    /// Names of the exercises that will be added, for the confirmation wording — adding
    /// rows to someone's catalog is still not something to do silently.
    var newExerciseNames: [String] {
        exercises.filter { $0.resolution.addsARow }.map(\.incomingName).sorted()
    }

    /// One auto-matched row, flattened across types so the review screen can list them
    /// together at the end.
    struct Match: Identifiable {
        let id: UUID
        let type: String
        let incomingName: String
        let localName: String?
    }

    /// Everything that matched something identical and was resolved without asking.
    ///
    /// Reported as a list and not only as a count: a number tells you the importer
    /// matched fourteen things, but not *which* fourteen, and checking it matched the
    /// right ones is the entire reason to look.
    var automaticMatches: [Match] {
        func collect<T>(_ decisions: [CatalogDecision<T>], _ type: String) -> [Match] {
            decisions
                .filter { $0.resolution == .identical }
                .map { Match(id: $0.incomingID, type: type, incomingName: $0.incomingName, localName: $0.localName) }
        }
        return (collect(exercises, "Exercise")
            + collect(equipment, "Equipment")
            + collect(muscles, "Muscle")
            + collect(exerciseCategories, "Exercise category")
            + collect(muscleCategories, "Muscle category"))
            .sorted { $0.incomingName.localizedCaseInsensitiveCompare($1.incomingName) == .orderedAscending }
    }
}

private extension Array {
    /// `count(where:)` is only available on newer toolchains for some element types;
    /// spelling it out keeps this readable at the five call sites above.
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
