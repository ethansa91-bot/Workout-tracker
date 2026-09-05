import Foundation
import SwiftData

/// Files what an EMOM or AMRAP section produced into a `SectionResultLog`.
///
/// One entry point for both runners, because the timing is easy to get wrong: the value
/// lives in `session.currentStepIndex`/`currentSetIndex`, and
/// `WorkoutSessionService.advanceSection` resets those the moment the section ends. Every
/// call must therefore happen *before* `onSectionComplete()`, not after.
enum SectionResultService {
    /// Records `value` for this pass of `section`, replacing the pass's existing row if
    /// there is one.
    ///
    /// Idempotent per `(session, section, repeatIndex)`, the same key
    /// `TimeSessionRunnerView.logStep` de-dupes on — a runner that is rebuilt and
    /// re-entered (a scrubbed pass, a resumed session) must not leave two rows for one
    /// pass, which would double-count a repeated section in the summary.
    @discardableResult
    static func record(
        session: WorkoutSession,
        section: WorkoutSection,
        value: Int,
        repeatIndex: Int,
        context: ModelContext
    ) -> SectionResultLog {
        let sectionID = section.id
        let existing = session.sectionResultLogs.first {
            $0.deletedAt == nil && $0.section?.id == sectionID && $0.repeatIndex == repeatIndex
        }

        let log: SectionResultLog
        if let existing {
            log = existing
        } else {
            log = SectionResultLog(
                session: session,
                section: section,
                recordGroupID: section.recordGroupID,
                sectionNameSnapshot: section.displayName,
                sectionType: section.sectionType,
                repeatIndex: repeatIndex
            )
            context.insert(log)
        }

        log.value = max(0, value)
        log.loggedAt = .now
        // Re-snapshotted on every write so a section renamed mid-session files under the
        // name it had when the result landed.
        log.recordGroupID = section.recordGroupID
        log.sectionNameSnapshot = section.displayName
        log.sectionType = section.sectionType
        log.markDirty()
        session.markDirty()
        try? context.save()
        return log
    }

    /// The best pass per tracked section in a finished session — what the end-of-workout
    /// card offers, and what a record is filed from.
    ///
    /// Grouped by `recordGroupID` rather than by section: a workout can legitimately
    /// contain the same benchmark twice, and both attempts compete for the one record.
    /// A repeated section's passes compete the same way — the best round count is the
    /// achievement, not the last one or the sum.
    static func bestResults(in session: WorkoutSession) -> [SectionResultLog] {
        var bestByGroup: [UUID: SectionResultLog] = [:]
        for log in session.sectionResultLogs where log.deletedAt == nil {
            // Only tracked sections have a group, and only they can set a record. An
            // untracked AMRAP still logs its rounds — that is what puts a number in
            // session history — it just has nothing to file them under.
            guard let groupID = log.recordGroupID, log.section?.tracksRecord == true else { continue }
            if let current = bestByGroup[groupID], current.value >= log.value { continue }
            bestByGroup[groupID] = log
        }
        return bestByGroup.values.sorted { $0.loggedAt < $1.loggedAt }
    }

    /// Files one candidate's round count as its record — the corrected value if
    /// `SectionRecordCard` was used to adjust it, otherwise the value the runner logged.
    /// Returns whether it actually became a new record.
    ///
    /// Called once per candidate when the session summary is dismissed, not when the
    /// session itself ends: the count comes off a counter tapped mid-effort, so a
    /// miscount is likely, and this is what lets the summary's review actually change
    /// what gets filed instead of racing a save that already happened before it was shown.
    ///
    /// Only ever upward: `sectionBeats` is the same gate `SectionRecordCard` used to show
    /// its own Save button disabled by, so a worse or unchanged number can't overwrite
    /// what's standing. Correcting one downward still means deleting it from the Records
    /// tab, the rule every record here follows.
    @discardableResult
    static func commitCorrectedResult(_ candidate: SectionResultLog, value: Int, context: ModelContext) -> Bool {
        guard let groupID = candidate.recordGroupID else { return false }
        let existing = PersonalRecordQueries.sectionRecord(groupID: groupID, context: context)

        // The corrected number is the achievement, so the result row is brought in line
        // with it whether or not it ends up beating the record — otherwise session
        // history would still show the miscount the review was used to fix.
        if candidate.value != value {
            candidate.value = value
            candidate.markDirty()
        }

        guard PersonalRecordQueries.sectionBeats(record: existing, value: value) else { return false }
        PersonalRecordQueries.setSectionRecord(
            groupID: groupID,
            name: candidate.displayName,
            kind: candidate.sectionType,
            value: value,
            existing: existing,
            context: context
        )
        promote(candidate, context: context)
        return true
    }

    /// Locks the section and makes sure it exists as a template — the two halves of "once
    /// you've done it once, it's fixed and reusable".
    ///
    /// Locking is stamped on *every* live section sharing the identity, not just the one
    /// performed: an in-workout section and a template copied out of it earlier are the
    /// same benchmark, and leaving either editable would let the record's meaning drift.
    ///
    /// Here rather than in `SectionRecordCard`, where it used to live: the automatic save
    /// at the end of a session and the card's manual correction both have to do it, and a
    /// second copy would be a second chance for one of them to stop.
    static func promote(_ candidate: SectionResultLog, context: ModelContext) {
        guard let section = candidate.section, let groupID = section.recordGroupID else { return }
        let shared = sectionsSharing(groupID: groupID, context: context)

        if !shared.contains(where: \.isTemplate) {
            // Copying out of a section that is about to be locked, which `saveAsTemplate`
            // deliberately permits — the copy is read-only with respect to the source, and
            // this is the one call that creates the identity's single template.
            let template = try? WorkoutSectionCloningService.saveAsTemplate(
                section, name: section.displayName, context: context
            )
            template?.recordLockedAt = .now
            template?.markDirty()
        }

        for row in shared where row.recordLockedAt == nil {
            row.recordLockedAt = .now
            row.markDirty()
        }
    }

    /// Every live section sharing `groupID`, in-workout and template alike — the rows a
    /// record lock has to be stamped onto.
    static func sectionsSharing(groupID: UUID, context: ModelContext) -> [WorkoutSection] {
        let descriptor = FetchDescriptor<WorkoutSection>(
            predicate: #Predicate { $0.recordGroupID == groupID && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
