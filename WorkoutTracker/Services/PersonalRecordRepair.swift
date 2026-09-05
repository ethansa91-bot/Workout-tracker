import Foundation
import SwiftData

/// A one-tap repair for personal records that shouldn't exist.
///
/// Deliberately self-contained: nothing in the app calls into this except the button in
/// `RecordsListView`, and nothing here is needed by any normal code path. Delete the
/// button and this file and the app is unchanged — which is the point, because this is a
/// stopgap for damage whose source hasn't been found yet, not a feature.
///
/// The six classes below are each already acknowledged somewhere in the codebase as
/// possible, but nothing removes them:
///
/// - **Phantom no-equipment.** A weighted record with `equipment == nil` — see
///   `RecordEquipmentBackfill`, which fixes these once per install and can never run
///   again. `RecordsListView` keys a nil equipment apart from a real one, so the
///   exercise shows its record twice, the second reading "No equipment".
/// - **Duplicates.** Two live records with the same facets. Sync can produce them, which
///   is why `RecordsListView` groups with a newest-wins loop rather than
///   `Dictionary(uniqueKeysWithValues:)` — it used to trap.
/// - **Empty.** A row the editor created and never saved a value into.
///   `PersonalRecordQueries.savedCombinations` already skips these; the list doesn't.
/// - **Orphans.** No exercise and no section group. Every query is exercise-predicated,
///   so nothing can see these — or delete them — while they keep an exercise or an
///   equipment permanently undeletable via `CatalogDeletionService.deletionBlockReason`.
/// - **Duplicate section records.** `sectionRecord(groupID:)` takes the newest of them;
///   the list renders every one as its own row.
/// - **Detached equipment.** A record pointing at equipment no longer attached to its
///   exercise. `RecordsListView` resolves a variant's equipment against
///   `exercise.equipmentItems`, so these *also* render as "No equipment" despite holding
///   a real reference — a phantom the backfill can't even see.
enum PersonalRecordRepair {

    /// Ids tombstoned by the last run, so it can be undone.
    ///
    /// Everything here soft-deletes, so nothing a run removes is actually gone — but
    /// without a list of what it touched there is no way to tell those rows apart from
    /// records deliberately deleted months ago. `UserDefaults` rather than a model: this
    /// is scaffolding for a stopgap, and it should leave nothing behind in the store.
    private static let lastRunIDsKey = "personalRecordRepair.lastRunIDs"
    private static let lastRunDateKey = "personalRecordRepair.lastRunDate"

    /// Rows this run tombstoned, accumulated as the passes go and written out at the end.
    private static var tombstonedThisRun: [UUID] = []

    /// What a run changed, for the summary shown afterwards.
    struct Report {
        var mergedPhantoms = 0
        var adoptedEquipment = 0
        var repointedDetached = 0
        var removedDuplicates = 0
        var mergedSameEquipmentName = 0
        var mergedSameValue = 0
        var removedEmpty = 0
        var removedOrphans = 0
        var removedDuplicateSections = 0
        var clearedMismatchedUnits = 0
        var removedUnattributable = 0

        var totalChanged: Int {
            mergedPhantoms + adoptedEquipment + repointedDetached + removedDuplicates
                + mergedSameEquipmentName + mergedSameValue
                + removedEmpty + removedOrphans + removedDuplicateSections
                + clearedMismatchedUnits + removedUnattributable
        }

        /// One line per class that actually did something, so a run that fixed one thing
        /// says so instead of printing six zeroes.
        var summary: String {
            guard totalChanged > 0 else { return "Nothing to fix — every record looks right." }
            var lines: [String] = []
            if mergedPhantoms > 0 { lines.append("Merged \(mergedPhantoms) \"No equipment\" duplicate\(s(mergedPhantoms)).") }
            if adoptedEquipment > 0 { lines.append("Attributed \(adoptedEquipment) record\(s(adoptedEquipment)) to their only equipment.") }
            if repointedDetached > 0 { lines.append("Re-pointed \(repointedDetached) record\(s(repointedDetached)) at detached equipment.") }
            if removedDuplicates > 0 { lines.append("Removed \(removedDuplicates) duplicate\(s(removedDuplicates)).") }
            if mergedSameEquipmentName > 0 { lines.append("Merged \(mergedSameEquipmentName) record\(s(mergedSameEquipmentName)) filed under a repeated equipment.") }
            if mergedSameValue > 0 { lines.append("Merged \(mergedSameValue) record\(s(mergedSameValue)) holding the same result.") }
            if removedEmpty > 0 { lines.append("Removed \(removedEmpty) empty record\(s(removedEmpty)).") }
            if removedOrphans > 0 { lines.append("Removed \(removedOrphans) record\(s(removedOrphans)) with no exercise.") }
            if removedDuplicateSections > 0 { lines.append("Removed \(removedDuplicateSections) duplicate section record\(s(removedDuplicateSections)).") }
            if clearedMismatchedUnits > 0 { lines.append("Detached \(clearedMismatchedUnits) record\(s(clearedMismatchedUnits)) from equipment measured in another unit.") }
            if removedUnattributable > 0 { lines.append("Removed \(removedUnattributable) record\(s(removedUnattributable)) set on no equipment, for exercises that have some.") }
            return lines.joined(separator: "\n")
        }

        private func s(_ count: Int) -> String { count == 1 ? "" : "s" }
    }

    /// The facets that make two records the same record.
    ///
    /// The same six `RecordsListView.RecordKey` carries. Redeclared rather than shared
    /// because that one is `private` to the view, and keeping this file removable in one
    /// piece matters more here than avoiding the duplicate — if the two ever disagree,
    /// the view's is the one that decides what the user sees.
    private struct Key: Hashable {
        let exerciseID: UUID
        let equipmentID: UUID?
        let isBodyweight: Bool
        let trackingMode: RepExerciseTrackingMode
        let executionTypeID: UUID?
        let isFollowAlong: Bool

        init?(_ record: PersonalRecord) {
            guard let exerciseID = record.exercise?.id else { return nil }
            self.exerciseID = exerciseID
            self.equipmentID = record.isBodyweight ? nil : record.equipment?.id
            self.isBodyweight = record.isBodyweight
            self.trackingMode = record.trackingMode
            self.executionTypeID = record.executionType?.id
            self.isFollowAlong = record.isFollowAlong
        }
    }

    static func run(context: ModelContext) -> Report {
        var report = Report()
        tombstonedThisRun = []

        report.removedOrphans = removeOrphans(in: liveRecords(context), context: context)
        report.removedEmpty = removeEmpty(in: liveRecords(context), context: context)
        // Re-fetched, like every pass: an empty section record tombstoned a line above is
        // still in the previous snapshot, and it could be the newest of its group — which
        // would merge a live record into a deleted one.
        report.removedDuplicateSections = dedupeSectionRecords(in: liveRecords(context), context: context)

        // Before attribution, so a record wrongly attached earlier is loose again and can
        // be re-attributed properly — or left alone.
        report.clearedMismatchedUnits = clearMismatchedEquipment(in: liveRecords(context), context: context)

        // Equipment is attributed before duplicates are collapsed: doing it the other way
        // round would compare a phantom against a real record on a key the phantom is
        // about to stop having, and leave both standing.
        let attributed = attributeEquipment(in: liveRecords(context), context: context)
        report.adoptedEquipment = attributed.adopted
        report.repointedDetached = attributed.repointed

        let deduped = dedupe(in: liveRecords(context), context: context)
        report.mergedPhantoms = deduped.phantoms
        report.removedDuplicates = deduped.others

        // After the key-based dedupe, which by construction can't reach either of these:
        // its key holds the equipment *id*, and both of these are about records whose ids
        // legitimately differ.
        report.mergedSameEquipmentName = mergeByEquipmentName(in: liveRecords(context), context: context)
        report.mergedSameValue = mergeByValue(in: liveRecords(context), context: context)

        // Last, so everything rescuable has already been rescued: attributed where there
        // was one candidate, merged into a real sibling where there was one to merge into.
        // What is left cannot be placed at all.
        report.removedUnattributable = removeUnattributable(in: liveRecords(context), context: context)

        if report.totalChanged > 0 { try? context.save() }
        UserDefaults.standard.set(tombstonedThisRun.map(\.uuidString), forKey: lastRunIDsKey)
        UserDefaults.standard.set(Date.now, forKey: lastRunDateKey)
        tombstonedThisRun = []
        return report
    }

    /// Soft-deletes and remembers, so `undoLastRun` can put it back.
    private static func tombstone<T: SyncableModel & PersistentModel>(_ model: T, id: UUID, context: ModelContext) {
        SyncDeletion.delete(model, context: context)
        tombstonedThisRun.append(id)
    }

    /// Restores everything the last run removed.
    ///
    /// Returns how many rows came back. Falls back to a time window when no run was
    /// recorded — earlier versions of this file deleted and merged without keeping a list,
    /// and those runs are exactly the ones worth being able to take back.
    static func undoLastRun(context: ModelContext) -> Int {
        let defaults = UserDefaults.standard
        let ids = Set((defaults.array(forKey: lastRunIDsKey) as? [String] ?? []).compactMap(UUID.init(uuidString:)))

        // No recorded list means the run predates this bookkeeping — the versions of this
        // file that took records without keeping a receipt are exactly the ones worth being
        // able to undo, so those fall back to a window. It is deliberately short: a record
        // deleted by hand a while back should stay deleted, and anything a repair took is
        // minutes old by the time anyone reaches for this.
        let window: Date? = ids.isEmpty ? Date.now.addingTimeInterval(-24 * 60 * 60) : nil
        let matching: Set<UUID>? = ids.isEmpty ? nil : ids

        var restored = 0
        restored += reviveRecords(matching: matching, deletedSince: window, context: context)
        restored += reviveEntries(matching: matching, deletedSince: window, context: context)

        defaults.removeObject(forKey: lastRunIDsKey)
        defaults.removeObject(forKey: lastRunDateKey)
        if restored > 0 { try? context.save() }
        return restored
    }

    /// Clears the tombstone on every row the filter accepts.
    ///
    /// Two near-identical passes rather than one generic: `id` is declared on each model
    /// rather than on `SyncableModel`, so there is nothing to write the shared version
    /// against that wouldn't cost more than the repetition.
    private static func reviveRecords(matching ids: Set<UUID>?, deletedSince: Date?, context: ModelContext) -> Int {
        var restored = 0
        for row in (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? [] {
            guard let deletedAt = row.deletedAt else { continue }
            if let ids, !ids.contains(row.id) { continue }
            if let deletedSince, deletedAt < deletedSince { continue }
            row.deletedAt = nil
            row.markDirty()
            restored += 1
        }
        return restored
    }

    private static func reviveEntries(matching ids: Set<UUID>?, deletedSince: Date?, context: ModelContext) -> Int {
        var restored = 0
        for row in (try? context.fetch(FetchDescriptor<PersonalRecordEntry>())) ?? [] {
            guard let deletedAt = row.deletedAt else { continue }
            if let ids, !ids.contains(row.id) { continue }
            if let deletedSince, deletedAt < deletedSince { continue }
            row.deletedAt = nil
            row.markDirty()
            restored += 1
        }
        return restored
    }

    /// Fetched fresh for every pass: soft deletes leave the row in place, so an earlier
    /// pass's tombstones are still present-and-live-looking in a snapshot taken before it.
    private static func liveRecords(_ context: ModelContext) -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.deletedAt == nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Removals

    private static func removeOrphans(in records: [PersonalRecord], context: ModelContext) -> Int {
        var removed = 0
        for record in records where record.deletedAt == nil
            && record.exercise == nil && record.sectionRecordGroupID == nil {
            tombstone(record, id: record.id, context: context)
            removed += 1
        }
        return removed
    }

    /// A record holding no value at all, and with no history to lose. The same emptiness
    /// `PersonalRecordQueries.hasValue` tests before filing a superseded value.
    private static func removeEmpty(in records: [PersonalRecord], context: ModelContext) -> Int {
        var removed = 0
        for record in records {
            guard record.deletedAt == nil else { continue }
            guard record.exercise != nil || record.sectionRecordGroupID != nil else { continue }
            guard record.reps == nil, record.weight == nil, record.holdSeconds == nil,
                  record.history.isEmpty
            else { continue }
            tombstone(record, id: record.id, context: context)
            removed += 1
        }
        return removed
    }

    private static func dedupeSectionRecords(in records: [PersonalRecord], context: ModelContext) -> Int {
        let sectionRecords = records.filter { $0.deletedAt == nil && $0.sectionRecordGroupID != nil }
        var removed = 0
        for (_, group) in Dictionary(grouping: sectionRecords, by: { $0.sectionRecordGroupID! }) where group.count > 1 {
            guard let survivor = newest(of: group) else { continue }
            for loser in group where loser !== survivor {
                merge(loser, into: survivor, context: context)
                removed += 1
            }
        }
        return removed
    }

    /// Detaches a record from equipment that measures weight in something else.
    ///
    /// A kg record cannot have been set on a vest that counts options: the number would be
    /// read as a different quantity entirely. `weightUnit` is stamped on the record itself
    /// and is the honest one — it says what the number meant when it was written, where the
    /// equipment link is just a pointer that something may have moved.
    ///
    /// This exists because an earlier version of `attributeEquipment` created exactly this
    /// state: it filled a nil equipment with `defaultWeightedEquipment` whenever the
    /// exercise had several options, without checking that the default measured the same
    /// thing. Clearing the link back to nil restores what those records said before, since
    /// nothing else about them was touched.
    private static func clearMismatchedEquipment(in records: [PersonalRecord], context: ModelContext) -> Int {
        var cleared = 0
        for record in records {
            guard record.deletedAt == nil, !record.isBodyweight,
                  let unit = record.weightUnit,
                  let equipment = record.equipment,
                  equipment.effectiveWeightUnit != unit
            else { continue }
            record.equipment = nil
            record.markDirty()
            for entry in record.history where entry.equipment?.id == equipment.id {
                entry.equipment = nil
                entry.markDirty()
            }
            cleared += 1
        }
        return cleared
    }

    /// Deletes a weighted record that records no equipment, for an exercise that has some.
    ///
    /// Such a record cannot be right: the exercise is only performed loaded, so the set
    /// behind the number was performed on *something*, and the row has lost which. Every
    /// pass above has already had its chance — a single candidate would have been adopted,
    /// a lone real sibling would have absorbed it — so what reaches here is a number with
    /// no way to say what it means, shown as a phantom "No equipment" twin beside the real
    /// records.
    ///
    /// The one genuinely destructive thing this file does, and deliberate: keeping it would
    /// mean either living with the phantom or attributing it by guesswork, and a guess that
    /// reads as a real record in the wrong unit is worse than a number you can re-enter.
    private static func removeUnattributable(in records: [PersonalRecord], context: ModelContext) -> Int {
        var removed = 0
        for record in records {
            guard record.deletedAt == nil, record.sectionRecordGroupID == nil,
                  record.equipment == nil, !record.isBodyweight,
                  let exercise = record.exercise,
                  !exercise.weightedEquipmentOptions.isEmpty
            else { continue }
            for entry in record.history {
                SyncDeletion.delete(entry, context: context)
            }
            tombstone(record, id: record.id, context: context)
            removed += 1
        }
        return removed
    }

    // MARK: - Equipment attribution

    /// Gives a record the equipment it must have been set on, where there is exactly one
    /// candidate — the "nothing to guess" rule `RecordEquipmentBackfill` applies, run on
    /// demand rather than once per install.
    ///
    /// A candidate has to match the record's stored `weightUnit`. A kg record cannot have
    /// been set on a weight vest that counts options, so equipment measured differently is
    /// not a candidate however few others there are. This is what a briefly-shipped version
    /// of this pass got wrong: it took `defaultWeightedEquipment` whenever the exercise had
    /// several options, which cheerfully filed barbell kilos under a level-based vest.
    ///
    /// Still nothing when two candidates share a unit. Choosing between a barbell and a
    /// dumbbell that both count kilos would invent history rather than recover it, and a
    /// wrong attribution reads as a real record while "No equipment" at least reads as a
    /// problem.
    private static func attributeEquipment(
        in records: [PersonalRecord],
        context: ModelContext
    ) -> (adopted: Int, repointed: Int) {
        var adopted = 0
        var repointed = 0

        for record in records {
            guard record.deletedAt == nil else { continue }
            guard let exercise = record.exercise, !record.isBodyweight else { continue }
            let options = exercise.weightedEquipmentOptions
            guard !options.isEmpty else { continue }

            // Whatever the record's weight is expressed in narrows the field: equipment
            // measured in something else cannot be where that number came from.
            let candidates = options.filter { candidate in
                guard let unit = record.weightUnit else { return true }
                return candidate.effectiveWeightUnit == unit
            }
            guard candidates.count == 1, let only = candidates.first else { continue }

            if let current = record.equipment {
                // Points at something real but detached from the exercise. Unlike a nil,
                // the reference still says which equipment was meant, so
                // `mergeByEquipmentName` can fold it in by that name without a guess — this
                // only rescues the case where there is a single candidate anyway.
                guard !options.contains(where: { $0.id == current.id }) else { continue }
                repoint(record, to: only, context: context)
                repointed += 1
            } else {
                repoint(record, to: only, context: context)
                adopted += 1
            }
        }
        return (adopted, repointed)
    }

    private static func repoint(_ record: PersonalRecord, to equipment: Equipment, context: ModelContext) {
        record.equipment = equipment
        record.markDirty()
        // History carries its own denormalised copy of the facet, so a record whose
        // equipment is corrected while its past still says otherwise would read as two
        // different lifts on one page.
        for entry in record.history where !entry.isBodyweight {
            entry.equipment = equipment
            entry.markDirty()
        }
    }

    // MARK: - Duplicates

    /// Collapses records sharing a key, keeping the newest.
    ///
    /// Newest wins, matching `PersonalRecordQueries.current` and `RecordsListView`'s own
    /// grouping — deliberately the opposite of `CatalogReconciliation.dedupe`, which keeps
    /// the *oldest* so two devices independently pick the same survivor. That rule is right
    /// for catalog rows nobody edits; here it would hide the value the list is currently
    /// showing, which reads as data loss rather than as a repair.
    ///
    /// A phantom is counted separately only for the summary: a nil-equipment row folding
    /// into a real one is the thing the user actually reported, and calling it a
    /// "duplicate" alongside the sync ones would bury it.
    private static func dedupe(
        in records: [PersonalRecord],
        context: ModelContext
    ) -> (phantoms: Int, others: Int) {
        var phantoms = 0
        var others = 0

        var groups: [Key: [PersonalRecord]] = [:]
        for record in records where record.deletedAt == nil && record.sectionRecordGroupID == nil {
            guard let key = Key(record) else { continue }
            groups[key, default: []].append(record)
        }

        for (_, group) in groups where group.count > 1 {
            guard let survivor = newest(of: group) else { continue }
            for loser in group where loser !== survivor {
                if loser.equipment == nil && !loser.isBodyweight { phantoms += 1 } else { others += 1 }
                merge(loser, into: survivor, context: context)
            }
        }

        // A phantom that shares no key with anything — the exercise has several equipment
        // options, so nothing could be guessed and nothing matched. Folded into the
        // exercise's own record for the same execution type and mode if there is exactly
        // one, since that is the record it is a shadow of.
        for record in records where record.sectionRecordGroupID == nil {
            guard record.equipment == nil, !record.isBodyweight,
                  let exercise = record.exercise,
                  !exercise.weightedEquipmentOptions.isEmpty,
                  record.deletedAt == nil
            else { continue }
            let siblings = records.filter {
                $0 !== record && $0.deletedAt == nil && !$0.isBodyweight
                    && $0.exercise?.id == exercise.id
                    && $0.executionType?.id == record.executionType?.id
                    && $0.trackingMode == record.trackingMode
                    && $0.isFollowAlong == record.isFollowAlong
                    && $0.equipment != nil
            }
            guard siblings.count == 1, let survivor = siblings.first else { continue }
            merge(record, into: survivor, context: context)
            phantoms += 1
        }

        return (phantoms, others)
    }

    /// Collapses an exercise's records that are filed under the same equipment *name*.
    ///
    /// Two `Equipment` rows can carry one name with different ids —
    /// `CatalogReconciliation.dedupe` keys on `id`, so same-name duplicates survive it. Two
    /// records pointing at such a pair are two keys, so `dedupe` above leaves both, and the
    /// Records screen shows the exercise's record twice under one label. Which of the two
    /// even resolves to a name depends on which id happens to be in
    /// `exercise.equipmentItems` at render time, which is why such a row can read "Barbell,
    /// Barbell" one moment and "No equipment" the next.
    ///
    /// Grouped by name rather than by identity for exactly that reason: the name is what
    /// the user sees, and two rows that read the same *are* the same as far as this is
    /// concerned. The other facets still separate — a hold and a set on one barbell stay
    /// two records.
    private static func mergeByEquipmentName(in records: [PersonalRecord], context: ModelContext) -> Int {
        struct NameKey: Hashable {
            let exerciseID: UUID
            let equipmentName: String
            let isBodyweight: Bool
            let trackingMode: RepExerciseTrackingMode
            let executionTypeID: UUID?
            let isFollowAlong: Bool
        }

        var groups: [NameKey: [PersonalRecord]] = [:]
        for record in records where record.deletedAt == nil && record.sectionRecordGroupID == nil {
            guard let exerciseID = record.exercise?.id,
                  !record.isBodyweight,
                  let name = record.equipment?.name
            else { continue }
            let key = NameKey(
                exerciseID: exerciseID,
                equipmentName: name,
                isBodyweight: record.isBodyweight,
                trackingMode: record.trackingMode,
                executionTypeID: record.executionType?.id,
                isFollowAlong: record.isFollowAlong
            )
            groups[key, default: []].append(record)
        }

        var merged = 0
        for (_, group) in groups where group.count > 1 {
            guard let survivor = preferredSurvivor(of: group) else { continue }
            for loser in group where loser !== survivor {
                merge(loser, into: survivor, context: context)
                merged += 1
            }
        }
        return merged
    }

    /// Collapses an exercise's records holding the identical result.
    ///
    /// One achievement recorded twice — the same reps at the same weight — however the two
    /// rows came to disagree about equipment or execution type. Deliberately blunter than
    /// the passes above: it doesn't care *why* they differ, only that keeping both would
    /// show one number twice.
    ///
    /// A record with no value is skipped rather than matched: several of those share
    /// "nothing" and are not the same achievement. `removeEmpty` has already taken the ones
    /// with no history to lose.
    private static func mergeByValue(in records: [PersonalRecord], context: ModelContext) -> Int {
        struct ValueKey: Hashable {
            let exerciseID: UUID
            let reps: Int?
            let weight: Double?
            let holdSeconds: Int?
            let isBodyweight: Bool
        }

        var groups: [ValueKey: [PersonalRecord]] = [:]
        for record in records where record.deletedAt == nil && record.sectionRecordGroupID == nil {
            guard let exerciseID = record.exercise?.id else { continue }
            guard record.reps != nil || record.weight != nil || record.holdSeconds != nil else { continue }
            let key = ValueKey(
                exerciseID: exerciseID,
                reps: record.reps,
                weight: record.weight,
                holdSeconds: record.holdSeconds,
                isBodyweight: record.isBodyweight
            )
            groups[key, default: []].append(record)
        }

        var merged = 0
        for (_, group) in groups where group.count > 1 {
            // Earliest, not newest. Every row here holds the identical number, so the only
            // thing that differs is when it was written — and the first time you did it is
            // when you did it. The other passes keep the newest because there the values
            // differ and the latest is the standing one.
            guard let survivor = preferredSurvivor(of: group, preferringOldest: true) else { continue }
            for loser in group where loser !== survivor {
                merge(loser, into: survivor, context: context)
                merged += 1
            }
        }
        return merged
    }

    /// The row to keep: one whose equipment the Records screen can actually resolve, and
    /// among those the newest.
    ///
    /// Resolution matters more than recency here. The screen looks a record's equipment id
    /// up in `exercise.equipmentItems` and renders "No equipment" when it isn't there, so
    /// keeping an unresolvable row — even a newer one — would leave the exercise labelled
    /// as having no equipment when it plainly has some.
    private static func preferredSurvivor(of group: [PersonalRecord], preferringOldest: Bool = false) -> PersonalRecord? {
        let resolvable = group.filter { record in
            guard let equipment = record.equipment, let exercise = record.exercise else { return false }
            return exercise.equipmentItems.contains { $0.id == equipment.id }
        }
        let candidates = resolvable.isEmpty ? group : resolvable
        return preferringOldest
            ? candidates.min { $0.updatedAt < $1.updatedAt }
            : newest(of: candidates)
    }

    /// Moves a loser's history onto the survivor, then tombstones it.
    ///
    /// History first, always: `historyStorage` cascades, so deleting a record takes its
    /// past with it. The loser's own current value becomes an entry too — it was a real
    /// result someone achieved, and dropping it is exactly the data loss this is meant to
    /// prevent.
    ///
    /// Soft delete via `SyncDeletion`, matching how the Records screen deletes a record:
    /// a hard delete would come straight back from another device.
    private static func merge(_ loser: PersonalRecord, into survivor: PersonalRecord, context: ModelContext) {
        if loser.reps != nil || loser.weight != nil || loser.holdSeconds != nil {
            let carried = PersonalRecordEntry(
                record: survivor,
                exercise: survivor.exercise,
                equipment: survivor.isBodyweight ? nil : survivor.equipment,
                executionType: survivor.executionType,
                isBodyweight: survivor.isBodyweight,
                isFollowAlong: survivor.isFollowAlong,
                trackingMode: survivor.trackingMode,
                weight: loser.weight,
                reps: loser.reps,
                holdSeconds: loser.holdSeconds,
                weightUnit: loser.weightUnit ?? survivor.weightUnit,
                sectionRecordGroupID: survivor.sectionRecordGroupID,
                sectionRecordKind: survivor.sectionRecordKind,
                sectionRecordName: survivor.sectionRecordName,
                // The record carries no achievement date of its own — the same stand-in
                // `PersonalRecordQueries.setRecord` uses when filing a superseded value.
                achievedAt: loser.updatedAt
            )
            context.insert(carried)
        }

        for entry in loser.history {
            entry.record = survivor
            // Re-stamped to the survivor's facets: the entry is now filed under a record
            // whose equipment and type may differ from the one it was written against,
            // and a mismatched facet renders as a different lift on the record's page.
            entry.exercise = survivor.exercise
            entry.equipment = survivor.isBodyweight ? nil : survivor.equipment
            entry.executionType = survivor.executionType
            entry.isBodyweight = survivor.isBodyweight
            entry.isFollowAlong = survivor.isFollowAlong
            entry.markDirty()
        }
        // Nothing clears `loser.historyStorage` afterwards: reassigning `entry.record` is
        // what moves an entry, and the inverse keeps both sides in step. Emptying the
        // array by hand here risked nulling out rows that now belong to the survivor —
        // and the `.cascade` rule it would be guarding against never fires, because this
        // is a tombstone rather than a `context.delete`.
        tombstone(loser, id: loser.id, context: context)
        survivor.markDirty()
    }

    private static func newest(of group: [PersonalRecord]) -> PersonalRecord? {
        group.max { $0.updatedAt < $1.updatedAt }
    }
}
