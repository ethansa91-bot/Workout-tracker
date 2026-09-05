import Foundation
import SwiftData

/// A manually-set personal record for an exercise — independent of session
/// history. Never overwritten automatically by a later logged set; only changes
/// when the user explicitly edits and saves it. Reuses `RepExerciseTrackingMode`
/// (from the max-hold-time rep-section feature) so a record is either weight × reps
/// or a max hold time, matching the same two shapes a set can be logged as.
@Model
final class PersonalRecord: SyncableModel {
    var id: UUID = UUID()
    var exercise: Exercise?
    /// Which equipment the record was set on. Records are kept per equipment — a
    /// barbell best and a dumbbell best aren't the same lift, and the same goes for a
    /// loaded hold vs. an unloaded one. nil for records made before this existed, and
    /// for holds performed with no load.
    var equipment: Equipment?
    /// Which execution type the record was set under. Always optional: nil is the general
    /// record for the exercise, kept and shown as its own row rather than folded into a
    /// type, and it stays the one every set files under until the exercise turns on
    /// `separateRecordsPerExecutionType`. Turning that on never rewrites what is already
    /// here — see `PersonalRecordQueries.current`.
    var executionType: ExecutionType?
    /// The unit the record's `weight` is expressed in. Previously re-derived at display
    /// time from the exercise's current equipment, which silently reinterpreted the
    /// number whenever that resolution changed.
    var weightUnit: String?
    /// A bodyweight record is the exercise done at body load — best measured in reps,
    /// with no weight and no equipment, so it never merges with a weighted record for
    /// the same exercise. Non-optional with a `false` default so records written before
    /// this existed decode correctly: every one of them was weighted or a hold.
    /// A Follow Along record is the load carried through a timed step, not a best hold or
    /// a best set — so it is its own record even for the same exercise, equipment and
    /// execution type. A discriminator rather than a third `RepExerciseTrackingMode` case,
    /// which would leak an option into the rep builder's own tracking picker that means
    /// nothing there. Non-optional with a `false` default, exactly as `isBodyweight` is.
    var isFollowAlong: Bool = false
    var isBodyweight: Bool = false
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    var weight: Double?
    var reps: Int?
    var holdSeconds: Int?

    /// Non-nil marks this as a *section* record — an EMOM or AMRAP round count — rather
    /// than an exercise one. None of the facets above apply to it: no exercise, no
    /// equipment, no execution type, and `trackingModeRaw` keeps its default and is
    /// ignored. The value lives in `reps`, read as a round count.
    ///
    /// Keyed on the section's `recordGroupID` rather than a relationship so the record
    /// survives its template being deleted, needs no CloudKit inverse, and is shared by
    /// every copy of the section — one "Cindy" record however many workouts use it.
    ///
    /// Every existing query is exercise-predicated (`PersonalRecordQueries.current`) or
    /// skips a nil exercise outright (`RecordsListView.variants`), so these rows are
    /// invisible to the exercise-record paths without those needing to know about them.
    var sectionRecordGroupID: UUID?
    /// `WorkoutSectionType.emom` or `.amrap` — what the Records list filters on, stored
    /// so the filter and the label don't need the template fetched (or still to exist).
    var sectionRecordKindRaw: String?
    /// Name snapshot for display; the live template's name wins when one is still around.
    var sectionRecordName: String?

    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// Superseded values, newest first via `history`. Cascades: a deleted record's past
    /// has nothing left to belong to. Optional at the type level because CloudKit
    /// requires it of every to-many relationship.
    @Relationship(deleteRule: .cascade, inverse: \PersonalRecordEntry.record)
    var historyStorage: [PersonalRecordEntry]?
    var history: [PersonalRecordEntry] {
        get { (historyStorage ?? []).filter { $0.deletedAt == nil }.sorted { $0.achievedAt > $1.achievedAt } }
        set { historyStorage = newValue }
    }

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        equipment: Equipment? = nil,
        executionType: ExecutionType? = nil,
        weightUnit: String? = nil,
        isBodyweight: Bool = false,
        isFollowAlong: Bool = false,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        weight: Double? = nil,
        reps: Int? = nil,
        holdSeconds: Int? = nil,
        sectionRecordGroupID: UUID? = nil,
        sectionRecordKind: WorkoutSectionType? = nil,
        sectionRecordName: String? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.equipment = equipment
        self.executionType = executionType
        self.weightUnit = weightUnit
        self.isBodyweight = isBodyweight
        self.isFollowAlong = isFollowAlong
        self.trackingModeRaw = trackingMode.rawValue
        self.weight = weight
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.sectionRecordGroupID = sectionRecordGroupID
        self.sectionRecordKindRaw = sectionRecordKind?.rawValue
        self.sectionRecordName = sectionRecordName
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }

    /// Whether this row is a section record rather than an exercise one.
    var isSectionRecord: Bool { sectionRecordGroupID != nil }

    /// nil for an exercise record, and for a section record whose stored kind is
    /// unreadable — callers treat both the same way, by ignoring the row.
    var sectionRecordKind: WorkoutSectionType? {
        get { sectionRecordKindRaw.flatMap(WorkoutSectionType.init(rawValue:)) }
        set { sectionRecordKindRaw = newValue?.rawValue }
    }
}
