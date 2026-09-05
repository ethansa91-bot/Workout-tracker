import Foundation
import SwiftData

/// What an EMOM or AMRAP section actually produced: a round count, one row per pass.
///
/// These two runners had nowhere to put a result. AMRAP's tapped tally lived in
/// `session.currentSetIndex` and EMOM's round in `currentStepIndex`, and
/// `WorkoutSessionService.setPositionForCurrentSection` resets both the moment the
/// session advances — so the number was destroyed on the way out of the section and
/// reached neither the summary nor history. This is the durable home for it, and the
/// value a section record is filed from.
///
/// Written for every AMRAP and every to-failure EMOM, not just record-tracking ones:
/// the row costs nothing and it is what lets these sections show a result in session
/// history at all.
@Model
final class SectionResultLog: SyncableModel {
    var id: UUID = UUID()
    var session: WorkoutSession?
    var section: WorkoutSection?

    /// Snapshotted from the section at log time, so the result survives the section
    /// being renamed, retyped, or deleted — the same reason `SetLog` keeps
    /// `exerciseNameSnapshot`. `recordGroupID` in particular is what the end-of-workout
    /// card groups by, and it must not change under a finished session.
    var recordGroupID: UUID?
    var sectionNameSnapshot: String = ""
    var sectionTypeRaw: String = WorkoutSectionType.amrap.rawValue

    /// Which 0-based pass produced this, matching `StepLog.repeatIndex` — a repeated
    /// section files one row per pass rather than overwriting itself.
    var repeatIndex: Int = 0

    /// Rounds completed. For a to-failure EMOM that is the rounds finished before the
    /// one the user failed; for AMRAP it is the tapped counter.
    var value: Int = 0

    var loggedAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        session: WorkoutSession? = nil,
        section: WorkoutSection? = nil,
        recordGroupID: UUID? = nil,
        sectionNameSnapshot: String = "",
        sectionType: WorkoutSectionType = .amrap,
        repeatIndex: Int = 0,
        value: Int = 0,
        loggedAt: Date = .now
    ) {
        self.id = id
        self.session = session
        self.section = section
        self.recordGroupID = recordGroupID
        self.sectionNameSnapshot = sectionNameSnapshot
        self.sectionTypeRaw = sectionType.rawValue
        self.repeatIndex = repeatIndex
        self.value = value
        self.loggedAt = loggedAt
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var sectionType: WorkoutSectionType {
        get { WorkoutSectionType(rawValue: sectionTypeRaw) ?? .amrap }
        set { sectionTypeRaw = newValue.rawValue }
    }

    /// The live section's name when it is still around, falling back to the snapshot —
    /// the same precedence `StepLog.displayTitle` uses.
    var displayName: String {
        if let section, section.deletedAt == nil { return section.displayName }
        return sectionNameSnapshot.isEmpty ? sectionType.fallbackSectionName : sectionNameSnapshot
    }
}
