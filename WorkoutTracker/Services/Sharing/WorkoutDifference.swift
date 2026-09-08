import Foundation
import SwiftData

/// One field or structural change between a follower's saved copy and what the
/// publisher's workout looks like now.
///
/// Mirrors `CatalogDifference`'s field/mine/theirs shape so `WorkoutUpdateReviewView` can
/// reuse `CatalogConflictDetailView`'s comparison-row look, but simpler: there's no merge
/// option here, just take theirs or keep mine, since a workout diff (unlike a catalog
/// row) has no meaning for a third "union the two" option.
struct WorkoutDifference: Identifiable {
    enum Kind { case setting, structure }

    let id = UUID()
    let kind: Kind
    let field: String
    let mine: String
    let theirs: String
    var takeTheirs: Bool = true
    /// Mutates local state to the incoming value, given the catalog rows the update
    /// actually resolved to. Takes `CatalogMerge.Resolved` rather than capturing it,
    /// because computing the diff must never itself run `CatalogMerge.apply` — that
    /// inserts and overwrites catalog rows, and a diff is shown before the user has
    /// decided whether to accept anything. `WorkoutUpdateService.applyInPlace`/
    /// `saveAsCopy` are the only two call sites, and both resolve the catalog immediately
    /// before calling this, never before. Called only when `takeTheirs` is true — "keep
    /// mine" is always a no-op, since the local value is already sitting there.
    let apply: (CatalogMerge.Resolved) -> Void
}

/// Computes what changed between a follower's existing `Workout` and a freshly
/// downloaded re-publish of it, matched section/step/entry by the `sourceSectionId`-style
/// ids `SharedWorkoutImporter` stamps at download time.
///
/// Deliberately read-only: everything here reads `local`'s existing models and the
/// incoming DTOs/catalog *plan* (never applies it), so showing this diff — including
/// backing out of it — never changes anything on disk. `CatalogNameResolver` below is
/// what makes that possible for the fields that reference the catalog.
///
/// A structural change to a list (a section/step/entry added, removed, or reordered)
/// collapses into one difference per list rather than one per item — a workout with five
/// small structural changes would otherwise bury the settings changes under a wall of
/// cryptic single-item rows. Field-by-field changes on a row present on both sides still
/// get their own difference each, exactly as `CatalogImportPlanner` does for a catalog
/// row's fields.
@MainActor
enum WorkoutDifferenceCalculator {
    static func compute(
        local: Workout,
        payload: SharedWorkoutPayload,
        catalog: CatalogImportPlan,
        context: ModelContext
    ) -> [WorkoutDifference] {
        let names = CatalogNameResolver(catalog)
        var diffs = workoutScalarDiffs(local: local, incoming: payload.workout)
        diffs.append(contentsOf: sectionListDiffs(local: local, incoming: payload.workout, names: names, context: context))
        return diffs
    }

    /// True when every difference is a setting, none structural — the "this update only
    /// changes settings" framing `WorkoutUpdateReviewView` leads with.
    static func isSettingsOnly(_ differences: [WorkoutDifference]) -> Bool {
        differences.allSatisfy { $0.kind == .setting }
    }

    /// What an incoming exercise/equipment/execution-type id would resolve to locally,
    /// and what to call it, read straight off `CatalogImportPlanner`'s decisions — the
    /// same matching a fresh download already did — without running `CatalogMerge.apply`.
    /// A row with no local match (`localID == nil`) is exactly the row `CatalogMerge`
    /// would create when the update is actually committed.
    private struct CatalogNameResolver {
        private let exercises: [UUID: CatalogDecision<ArchiveExercise>]
        private let executionTypes: [UUID: CatalogDecision<ArchiveExecutionType>]

        init(_ catalog: CatalogImportPlan) {
            exercises = Dictionary(uniqueKeysWithValues: catalog.exercises.map { ($0.incomingID, $0) })
            executionTypes = Dictionary(uniqueKeysWithValues: catalog.executionTypes.map { ($0.incomingID, $0) })
        }

        func exerciseLocalID(_ id: UUID?) -> UUID? { id.flatMap { exercises[$0]?.localID } }
        func exerciseName(_ id: UUID?) -> String { id.flatMap { exercises[$0]?.incomingName } ?? "—" }
        func executionTypeLocalID(_ id: UUID?) -> UUID? { id.flatMap { executionTypes[$0]?.localID } }
        func executionTypeName(_ id: UUID?) -> String { id.flatMap { executionTypes[$0]?.incomingName } ?? "—" }
    }

    // MARK: - Workout scalars

    private static func workoutScalarDiffs(local: Workout, incoming: ArchiveWorkout) -> [WorkoutDifference] {
        var diffs: [WorkoutDifference] = []
        if local.name != incoming.name {
            let newValue = incoming.name
            diffs.append(WorkoutDifference(kind: .setting, field: "Name", mine: local.name, theirs: newValue) { _ in
                local.name = newValue
            })
        }
        let localNotes = local.notes ?? ""
        let incomingNotes = incoming.notes ?? ""
        if localNotes != incomingNotes {
            let newValue = incoming.notes
            diffs.append(WorkoutDifference(
                kind: .setting, field: "Notes",
                mine: localNotes.isEmpty ? "—" : localNotes,
                theirs: incomingNotes.isEmpty ? "—" : incomingNotes
            ) { _ in
                local.notes = newValue
            })
        }
        return diffs
    }

    // MARK: - Sections

    private static func sectionListDiffs(
        local: Workout, incoming: ArchiveWorkout, names: CatalogNameResolver, context: ModelContext
    ) -> [WorkoutDifference] {
        var diffs: [WorkoutDifference] = []
        let localSections = local.sortedSections
        let incomingSections = incoming.sections
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }

        var localBySource: [UUID: WorkoutSection] = [:]
        for section in localSections {
            if let sourceID = section.sourceSectionId { localBySource[sourceID] = section }
        }

        var matchedLocalIDs: Set<UUID> = []
        var matchedPairs: [(WorkoutSection, ArchiveSection)] = []
        var addedSections: [ArchiveSection] = []
        for incomingSection in incomingSections {
            if let match = localBySource[incomingSection.id] {
                matchedLocalIDs.insert(match.id)
                matchedPairs.append((match, incomingSection))
            } else {
                addedSections.append(incomingSection)
            }
        }
        let removedSections = localSections.filter { $0.sourceSectionId != nil && !matchedLocalIDs.contains($0.id) }

        let localMatchedOrder = localSections.compactMap { matchedLocalIDs.contains($0.id) ? $0.sourceSectionId : nil }
        let incomingMatchedOrder = incomingSections.compactMap { localBySource[$0.id] != nil ? $0.id : nil }
        let reordered = localMatchedOrder != incomingMatchedOrder

        if let diff = listStructureDifference(
            field: "Sections",
            addedNames: addedSections.map { $0.name ?? ($0.sectionTypeRaw.capitalized + " Section") },
            removedNames: removedSections.map(\.displayName),
            reordered: reordered
        ) {
            diffs.append(WorkoutDifference(kind: diff.kind, field: diff.field, mine: diff.mine, theirs: diff.theirs) { resolved in
                for section in removedSections {
                    SyncDeletion.delete(section, context: context)
                }
                for sectionDTO in addedSections {
                    SharedWorkoutImporter.buildSection(
                        from: sectionDTO, into: local,
                        exercises: resolved.exercises, equipment: resolved.equipment, executionTypes: resolved.executionTypes,
                        context: context
                    )
                }
                let survivorsBySource = Dictionary(uniqueKeysWithValues: matchedPairs.map { ($0.0.sourceSectionId!, $0.0) })
                let newlyAddedBySource = Dictionary(uniqueKeysWithValues: local.sections.compactMap { section -> (UUID, WorkoutSection)? in
                    guard let sourceID = section.sourceSectionId, addedSections.contains(where: { $0.id == sourceID }) else { return nil }
                    return (sourceID, section)
                })
                let ordered = incomingSections.compactMap { survivorsBySource[$0.id] ?? newlyAddedBySource[$0.id] }
                WorkoutSection.resequence(ordered)
            })
        }

        for (localSection, incomingSection) in matchedPairs {
            diffs.append(contentsOf: sectionScalarDiffs(local: localSection, incoming: incomingSection))
            diffs.append(contentsOf: stepListDiffs(local: localSection, incoming: incomingSection, names: names, context: context))
            diffs.append(contentsOf: repExerciseListDiffs(local: localSection, incoming: incomingSection, names: names, context: context))
            diffs.append(contentsOf: quickExerciseListDiffs(local: localSection, incoming: incomingSection, names: names, context: context))
        }

        return diffs
    }

    private static func sectionScalarDiffs(local: WorkoutSection, incoming: ArchiveSection) -> [WorkoutDifference] {
        var diffs: [WorkoutDifference] = []
        let prefix = "\(local.displayName) · "

        func add<T: Equatable>(_ label: String, _ mine: T, _ theirs: T, mineText: String? = nil, theirsText: String? = nil, apply: @escaping () -> Void) {
            guard mine != theirs else { return }
            diffs.append(WorkoutDifference(
                kind: .setting, field: prefix + label,
                mine: mineText ?? "\(mine)", theirs: theirsText ?? "\(theirs)",
                apply: { _ in apply() }
            ))
        }

        let incomingName = incoming.name ?? ""
        add("Name", local.name ?? "", incomingName, mineText: local.name ?? "—", theirsText: incomingName.isEmpty ? "—" : incomingName) {
            local.name = incoming.name
        }
        let incomingDescription = incoming.sectionDescription ?? ""
        add("Description", local.sectionDescription ?? "", incomingDescription, mineText: local.sectionDescription ?? "—", theirsText: incomingDescription.isEmpty ? "—" : incomingDescription) {
            local.sectionDescription = incoming.sectionDescription
        }
        add("Autostart", local.autostart, incoming.autostart, mineText: local.autostart ? "On" : "Off", theirsText: incoming.autostart ? "On" : "Off") {
            local.autostart = incoming.autostart
        }
        add("Repeat count", local.repeatCount, incoming.repeatCount) {
            local.repeatCount = incoming.repeatCount
        }
        let incomingGetReady = incoming.getReadySeconds ?? 0
        add("Get ready", local.getReadySeconds, incomingGetReady, mineText: "\(local.getReadySeconds)s", theirsText: "\(incomingGetReady)s") {
            local.getReadySeconds = incomingGetReady
        }
        let incomingRepeatsGetReady = incoming.repeatsGetReadyEachPass ?? true
        add("Repeat get ready each pass", local.repeatsGetReadyEachPass, incomingRepeatsGetReady, mineText: local.repeatsGetReadyEachPass ? "On" : "Off", theirsText: incomingRepeatsGetReady ? "On" : "Off") {
            local.repeatsGetReadyEachPass = incomingRepeatsGetReady
        }
        let incomingSectionRest = incoming.sectionRestSeconds ?? 0
        add("Section rest", local.sectionRestSeconds, incomingSectionRest, mineText: "\(local.sectionRestSeconds)s", theirsText: "\(incomingSectionRest)s") {
            local.sectionRestSeconds = incomingSectionRest
        }
        if local.sectionType == .emom {
            add("EMOM rounds", local.emomRoundCount, incoming.emomRoundCount) {
                local.emomRoundCount = incoming.emomRoundCount
            }
            let incomingToFailure = incoming.emomToFailure ?? false
            add("To failure", local.emomToFailure, incomingToFailure, mineText: local.emomToFailure ? "On" : "Off", theirsText: incomingToFailure ? "On" : "Off") {
                local.emomToFailure = incomingToFailure
            }
        }
        if local.sectionType == .amrap {
            add("AMRAP duration", local.amrapDurationSeconds, incoming.amrapDurationSeconds, mineText: "\(local.amrapDurationSeconds)s", theirsText: "\(incoming.amrapDurationSeconds)s") {
                local.amrapDurationSeconds = incoming.amrapDurationSeconds
            }
        }

        return diffs
    }

    // MARK: - Time steps

    private static func stepListDiffs(
        local: WorkoutSection, incoming: ArchiveSection, names: CatalogNameResolver, context: ModelContext
    ) -> [WorkoutDifference] {
        var diffs: [WorkoutDifference] = []
        let localSteps = local.sortedTimeSteps
        let incomingSteps = incoming.timeSteps.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }

        var localBySource: [UUID: TimeSectionStep] = [:]
        for step in localSteps {
            if let sourceID = step.sourceStepId { localBySource[sourceID] = step }
        }

        var matchedIDs: Set<UUID> = []
        var matchedPairs: [(TimeSectionStep, ArchiveTimeStep)] = []
        var addedSteps: [ArchiveTimeStep] = []
        for incomingStep in incomingSteps {
            if let match = localBySource[incomingStep.id] {
                matchedIDs.insert(match.id)
                matchedPairs.append((match, incomingStep))
            } else {
                addedSteps.append(incomingStep)
            }
        }
        let removedSteps = localSteps.filter { $0.sourceStepId != nil && !matchedIDs.contains($0.id) }

        let localOrder = localSteps.compactMap { matchedIDs.contains($0.id) ? $0.sourceStepId : nil }
        let incomingOrder = incomingSteps.compactMap { localBySource[$0.id] != nil ? $0.id : nil }

        if let diff = listStructureDifference(
            field: "\(local.displayName) · Steps",
            addedNames: addedSteps.map(\.stepTypeRaw),
            removedNames: removedSteps.map(\.displayTitle),
            reordered: localOrder != incomingOrder
        ) {
            diffs.append(WorkoutDifference(kind: diff.kind, field: diff.field, mine: diff.mine, theirs: diff.theirs) { resolved in
                for step in removedSteps { SyncDeletion.delete(step, context: context) }
                for stepDTO in addedSteps {
                    SharedWorkoutImporter.buildTimeStep(from: stepDTO, into: local, exercises: resolved.exercises, equipment: resolved.equipment, executionTypes: resolved.executionTypes, context: context)
                }
                let survivorsBySource = Dictionary(uniqueKeysWithValues: matchedPairs.map { ($0.0.sourceStepId!, $0.0) })
                let newlyAddedBySource = Dictionary(uniqueKeysWithValues: local.timeSteps.compactMap { step -> (UUID, TimeSectionStep)? in
                    guard let sourceID = step.sourceStepId, addedSteps.contains(where: { $0.id == sourceID }) else { return nil }
                    return (sourceID, step)
                })
                let ordered = incomingSteps.compactMap { survivorsBySource[$0.id] ?? newlyAddedBySource[$0.id] }
                TimeSectionStep.resequence(ordered)
            })
        }

        for (localStep, incomingStep) in matchedPairs {
            let prefix = "\(local.displayName) · \(localStep.displayTitle) · "
            let incomingExerciseLocalID = names.exerciseLocalID(incomingStep.exerciseID)
            if localStep.exercise?.id != incomingExerciseLocalID {
                let incomingExerciseID = incomingStep.exerciseID
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Exercise", mine: localStep.exercise?.name ?? "—", theirs: names.exerciseName(incomingExerciseID)) { resolved in
                    localStep.exercise = incomingExerciseID.flatMap { resolved.exercises[$0] }
                })
            }
            if localStep.durationSeconds != incomingStep.durationSeconds {
                let newValue = incomingStep.durationSeconds
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Duration", mine: "\(localStep.durationSeconds)s", theirs: "\(newValue)s") { _ in
                    localStep.durationSeconds = newValue
                })
            }
            let incomingExecutionTypeLocalID = names.executionTypeLocalID(incomingStep.executionTypeID)
            if localStep.executionType?.id != incomingExecutionTypeLocalID {
                let incomingExecutionTypeID = incomingStep.executionTypeID
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Execution type", mine: localStep.executionType?.name ?? "—", theirs: names.executionTypeName(incomingExecutionTypeID)) { resolved in
                    guard let id = incomingExecutionTypeID, let type = resolved.executionTypes[id],
                          localStep.exercise?.executionTypes.contains(where: { $0.id == type.id }) == true
                    else {
                        localStep.executionType = nil
                        return
                    }
                    localStep.executionType = type
                })
            }
            if localStep.startingWeight != incomingStep.startingWeight {
                let newValue = incomingStep.startingWeight
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Starting weight", mine: localStep.startingWeight.map { "\($0)" } ?? "—", theirs: newValue.map { "\($0)" } ?? "—") { _ in
                    localStep.startingWeight = newValue
                })
            }
        }

        return diffs
    }

    // MARK: - Rep exercises

    private static func repExerciseListDiffs(
        local: WorkoutSection, incoming: ArchiveSection, names: CatalogNameResolver, context: ModelContext
    ) -> [WorkoutDifference] {
        var diffs: [WorkoutDifference] = []
        let localEntries = local.sortedRepExercises
        let incomingEntries = incoming.repExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }

        var localBySource: [UUID: RepSectionExercise] = [:]
        for entry in localEntries {
            if let sourceID = entry.sourceRepExerciseId { localBySource[sourceID] = entry }
        }

        var matchedIDs: Set<UUID> = []
        var matchedPairs: [(RepSectionExercise, ArchiveRepExercise)] = []
        var addedEntries: [ArchiveRepExercise] = []
        for incomingEntry in incomingEntries {
            if let match = localBySource[incomingEntry.id] {
                matchedIDs.insert(match.id)
                matchedPairs.append((match, incomingEntry))
            } else {
                addedEntries.append(incomingEntry)
            }
        }
        let removedEntries = localEntries.filter { $0.sourceRepExerciseId != nil && !matchedIDs.contains($0.id) }

        let localOrder = localEntries.compactMap { matchedIDs.contains($0.id) ? $0.sourceRepExerciseId : nil }
        let incomingOrder = incomingEntries.compactMap { localBySource[$0.id] != nil ? $0.id : nil }

        if let diff = listStructureDifference(
            field: "\(local.displayName) · Exercises",
            addedNames: addedEntries.map { names.exerciseName($0.exerciseID) },
            removedNames: removedEntries.map(\.displayTitle),
            reordered: localOrder != incomingOrder
        ) {
            diffs.append(WorkoutDifference(kind: diff.kind, field: diff.field, mine: diff.mine, theirs: diff.theirs) { resolved in
                for entry in removedEntries { SyncDeletion.delete(entry, context: context) }
                for entryDTO in addedEntries {
                    SharedWorkoutImporter.buildRepExercise(from: entryDTO, into: local, exercises: resolved.exercises, equipment: resolved.equipment, executionTypes: resolved.executionTypes, context: context)
                }
                let survivorsBySource = Dictionary(uniqueKeysWithValues: matchedPairs.map { ($0.0.sourceRepExerciseId!, $0.0) })
                let newlyAddedBySource = Dictionary(uniqueKeysWithValues: local.repExercises.compactMap { entry -> (UUID, RepSectionExercise)? in
                    guard let sourceID = entry.sourceRepExerciseId, addedEntries.contains(where: { $0.id == sourceID }) else { return nil }
                    return (sourceID, entry)
                })
                let ordered = incomingEntries.compactMap { survivorsBySource[$0.id] ?? newlyAddedBySource[$0.id] }
                RepSectionExercise.resequence(ordered)
            })
        }

        for (localEntry, incomingEntry) in matchedPairs {
            let prefix = "\(local.displayName) · \(localEntry.displayTitle) · "
            let incomingExerciseLocalID = names.exerciseLocalID(incomingEntry.exerciseID)
            if localEntry.exercise?.id != incomingExerciseLocalID {
                let incomingExerciseID = incomingEntry.exerciseID
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Exercise", mine: localEntry.exercise?.name ?? "—", theirs: names.exerciseName(incomingExerciseID)) { resolved in
                    localEntry.exercise = incomingExerciseID.flatMap { resolved.exercises[$0] }
                })
            }
            if localEntry.targetSets != incomingEntry.targetSets {
                let newValue = incomingEntry.targetSets
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Sets", mine: "\(localEntry.targetSets)", theirs: "\(newValue)") { _ in
                    localEntry.targetSets = newValue
                })
            }
            let localRest = localEntry.customRestSeconds
            if localRest != incomingEntry.customRestSeconds {
                let newValue = incomingEntry.customRestSeconds
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Rest", mine: localRest.map { "\($0)s" } ?? "Default", theirs: newValue.map { "\($0)s" } ?? "Default") { _ in
                    localEntry.customRestSeconds = newValue
                })
            }
            let incomingMode = RepExerciseTrackingMode(rawValue: incomingEntry.trackingModeRaw) ?? .repsWeight
            if localEntry.trackingMode != incomingMode {
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Tracking", mine: localEntry.trackingMode.rawValue, theirs: incomingMode.rawValue) { _ in
                    localEntry.trackingModeRaw = incomingMode.rawValue
                })
            }
            let incomingExecutionTypeLocalID = names.executionTypeLocalID(incomingEntry.executionTypeID)
            if localEntry.executionType?.id != incomingExecutionTypeLocalID {
                let incomingExecutionTypeID = incomingEntry.executionTypeID
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Execution type", mine: localEntry.executionType?.name ?? "—", theirs: names.executionTypeName(incomingExecutionTypeID)) { resolved in
                    guard let id = incomingExecutionTypeID, let type = resolved.executionTypes[id],
                          localEntry.exercise?.executionTypes.contains(where: { $0.id == type.id }) == true
                    else {
                        localEntry.executionType = nil
                        return
                    }
                    localEntry.executionType = type
                })
            }
            if localEntry.startingWeight != incomingEntry.startingWeight {
                let newValue = incomingEntry.startingWeight
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Starting weight", mine: localEntry.startingWeight.map { "\($0)" } ?? "—", theirs: newValue.map { "\($0)" } ?? "—") { _ in
                    localEntry.startingWeight = newValue
                })
            }
            if localEntry.startingReps != incomingEntry.startingReps {
                let newValue = incomingEntry.startingReps
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Starting reps", mine: localEntry.startingReps.map { "\($0)" } ?? "—", theirs: newValue.map { "\($0)" } ?? "—") { _ in
                    localEntry.startingReps = newValue
                })
            }
        }

        return diffs
    }

    // MARK: - Quick exercises (EMOM/AMRAP)

    private static func quickExerciseListDiffs(
        local: WorkoutSection, incoming: ArchiveSection, names: CatalogNameResolver, context: ModelContext
    ) -> [WorkoutDifference] {
        var diffs: [WorkoutDifference] = []
        let localEntries = local.sortedQuickExercises
        let incomingEntries = incoming.quickExercises.filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }

        var localBySource: [UUID: SectionExerciseEntry] = [:]
        for entry in localEntries {
            if let sourceID = entry.sourceEntryId { localBySource[sourceID] = entry }
        }

        var matchedIDs: Set<UUID> = []
        var matchedPairs: [(SectionExerciseEntry, ArchiveQuickExercise)] = []
        var addedEntries: [ArchiveQuickExercise] = []
        for incomingEntry in incomingEntries {
            if let match = localBySource[incomingEntry.id] {
                matchedIDs.insert(match.id)
                matchedPairs.append((match, incomingEntry))
            } else {
                addedEntries.append(incomingEntry)
            }
        }
        let removedEntries = localEntries.filter { $0.sourceEntryId != nil && !matchedIDs.contains($0.id) }

        let localOrder = localEntries.compactMap { matchedIDs.contains($0.id) ? $0.sourceEntryId : nil }
        let incomingOrder = incomingEntries.compactMap { localBySource[$0.id] != nil ? $0.id : nil }

        if let diff = listStructureDifference(
            field: "\(local.displayName) · Exercises",
            addedNames: addedEntries.map { names.exerciseName($0.exerciseID) },
            removedNames: removedEntries.map(\.displayTitle),
            reordered: localOrder != incomingOrder
        ) {
            diffs.append(WorkoutDifference(kind: diff.kind, field: diff.field, mine: diff.mine, theirs: diff.theirs) { resolved in
                for entry in removedEntries { SyncDeletion.delete(entry, context: context) }
                for entryDTO in addedEntries {
                    SharedWorkoutImporter.buildQuickExercise(from: entryDTO, into: local, exercises: resolved.exercises, executionTypes: resolved.executionTypes, context: context)
                }
                let survivorsBySource = Dictionary(uniqueKeysWithValues: matchedPairs.map { ($0.0.sourceEntryId!, $0.0) })
                let newlyAddedBySource = Dictionary(uniqueKeysWithValues: local.quickExercises.compactMap { entry -> (UUID, SectionExerciseEntry)? in
                    guard let sourceID = entry.sourceEntryId, addedEntries.contains(where: { $0.id == sourceID }) else { return nil }
                    return (sourceID, entry)
                })
                let ordered = incomingEntries.compactMap { survivorsBySource[$0.id] ?? newlyAddedBySource[$0.id] }
                SectionExerciseEntry.resequence(ordered)
            })
        }

        for (localEntry, incomingEntry) in matchedPairs {
            let prefix = "\(local.displayName) · \(localEntry.displayTitle) · "
            let incomingExerciseLocalID = names.exerciseLocalID(incomingEntry.exerciseID)
            if localEntry.exercise?.id != incomingExerciseLocalID {
                let incomingExerciseID = incomingEntry.exerciseID
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Exercise", mine: localEntry.exercise?.name ?? "—", theirs: names.exerciseName(incomingExerciseID)) { resolved in
                    localEntry.exercise = incomingExerciseID.flatMap { resolved.exercises[$0] }
                })
            }
            if localEntry.targetReps != incomingEntry.targetReps {
                let newValue = incomingEntry.targetReps
                diffs.append(WorkoutDifference(kind: .setting, field: prefix + "Reps", mine: "\(localEntry.targetReps)", theirs: "\(newValue)") { _ in
                    localEntry.targetReps = newValue
                })
            }
        }

        return diffs
    }

    // MARK: - Helpers

    private struct ListStructureSummary {
        let kind: WorkoutDifference.Kind
        let field: String
        let mine: String
        let theirs: String
    }

    private static func listStructureDifference(
        field: String, addedNames: [String], removedNames: [String], reordered: Bool
    ) -> ListStructureSummary? {
        guard !addedNames.isEmpty || !removedNames.isEmpty || reordered else { return nil }
        var minePartsOnly: [String] = []
        var theirsPartsOnly: [String] = []
        if !removedNames.isEmpty { minePartsOnly.append("only yours: \(removedNames.joined(separator: ", "))") }
        if !addedNames.isEmpty { theirsPartsOnly.append("added: \(addedNames.joined(separator: ", "))") }
        if reordered { theirsPartsOnly.append("reordered") }
        return ListStructureSummary(
            kind: .structure, field: field,
            mine: minePartsOnly.isEmpty ? "No change" : minePartsOnly.joined(separator: "; "),
            theirs: theirsPartsOnly.isEmpty ? "No change" : theirsPartsOnly.joined(separator: "; ")
        )
    }
}
