import Foundation
import SwiftData

enum RepExerciseTrackingMode: String, Codable {
    case repsWeight, maxHoldTime
}

@Model
final class RepSectionExercise: SyncableModel, Orderable {
    var id: UUID = UUID()
    var section: WorkoutSection?
    var sortOrder: Int = 0
    var exercise: Exercise?
    var targetSets: Int = 0
    /// nil falls back to `AppSettings.defaultRestSeconds`.
    var customRestSeconds: Int?
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    /// Only meaningful when `trackingMode == .maxHoldTime` — seconds between
    /// pressing Start and the stopwatch actually beginning to count up.
    var headStartSeconds: Int = 3
    /// Offer the "Body" position on this entry's weight stepper. Only settable when the
    /// exercise itself is marked `allowsBodyweight`.
    var allowsBodyweight: Bool = false
    /// Log each set twice, once per side. Only settable when the exercise is marked
    /// `isOneSided`, and only for `.repsWeight` tracking.
    var tracksSides: Bool = false
    /// Which weighted equipment this workout uses for the exercise, when the exercise
    /// has more than one attached. nil falls back to the exercise's own resolution.
    var preferredEquipment: Equipment?
    /// This entry's default load is bodyweight rather than any weighted equipment.
    /// Distinct from `allowsBodyweight`, which only *offers* the Body position on the
    /// stepper: this makes it the starting selection. `preferredEquipment` is ignored
    /// while this is true. Non-optional with a `false` default so entries written
    /// before it existed decode correctly — every one of them was weighted.
    var prefersBodyweight: Bool = false
    /// The weight a fresh set of this exercise prefills at when there's no personal
    /// record and no prior logged set to seed from instead — see `recordSeed` in
    /// `RepSessionRunnerView`. nil means no override: the runner falls back to its own
    /// existing guess (the equipment's lightest preset) exactly as it did before this
    /// existed. Never used once a record or a prior set exists, whatever this holds.
    var startingWeight: Double?
    /// The rep-count counterpart to `startingWeight`, for `.repsWeight` tracking only —
    /// a max-hold set has no rep count to seed. nil falls back to the runner's own
    /// hardcoded guess, unchanged.
    var startingReps: Int?
    /// How this workout performs the exercise — explosive, slow, held. nil is a real
    /// value, not a missing one: "unspecified" stays a choice however many types the
    /// exercise carries, and it is what an entry created before this existed reads as.
    /// The runner can override it in the moment; this is the default it starts from.
    var executionType: ExecutionType?
    /// Whether this entry follows its exercise's progression ladder.
    ///
    /// On by default — a ladder is set up deliberately, so a workout using that exercise
    /// should follow it. Off pins the entry to exactly the exercise written: no Level
    /// line, and `resolvedExercise` stops substituting the reached rung.
    var progressionEnabled: Bool = true
    /// Whether the live runner can change this entry's equipment mid-workout. Off fixes
    /// it at whatever the builder set — a restriction on the *runner's* own menu only;
    /// the builder itself is never affected. Unrelated to Bodyweight: switching to
    /// Bodyweight from the stepper's own bottom-of-ladder prompt is gated solely by
    /// `allowsBodyweight`, not this. Non-optional with a `true` default so every entry
    /// written before this existed stays exactly as editable as it always was.
    var equipmentEditable: Bool = true
    /// The execution-type counterpart to `equipmentEditable` — off fixes this entry's
    /// execution type at whatever the builder set, for the same runner-only reason.
    var executionTypeEditable: Bool = true
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    /// The publisher's `ArchiveRepExercise.id`, for the same reason `WorkoutSection`
    /// carries `sourceSectionId` one level up — see that field's doc comment.
    var sourceRepExerciseId: UUID?

    /// Exists only to satisfy CloudKit's "every relationship needs an inverse" rule for
    /// `SetLog.repSectionExercise` — nothing in the app reads or writes this back-reference.
    @Relationship(inverse: \SetLog.repSectionExercise)
    var setLogs: [SetLog]?

    init(
        id: UUID = UUID(),
        section: WorkoutSection? = nil,
        sortOrder: Int,
        exercise: Exercise? = nil,
        targetSets: Int,
        customRestSeconds: Int? = nil,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        headStartSeconds: Int = 3,
        allowsBodyweight: Bool = false,
        tracksSides: Bool = false,
        preferredEquipment: Equipment? = nil,
        prefersBodyweight: Bool = false,
        executionType: ExecutionType? = nil,
        progressionEnabled: Bool = true
    ) {
        self.id = id
        self.section = section
        self.sortOrder = sortOrder
        self.exercise = exercise
        self.targetSets = targetSets
        self.customRestSeconds = customRestSeconds
        self.trackingModeRaw = trackingMode.rawValue
        self.headStartSeconds = headStartSeconds
        self.allowsBodyweight = allowsBodyweight
        self.tracksSides = tracksSides
        self.preferredEquipment = preferredEquipment
        self.prefersBodyweight = prefersBodyweight
        self.executionType = executionType
        self.progressionEnabled = progressionEnabled
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }

    /// What this entry is called wherever it's listed. The *plan's* type — a runner that
    /// lets the type be overridden mid-workout composes its own heading from the live
    /// choice instead, since that is what the sets it logs will carry.
    var displayTitle: String {
        ExerciseNaming.title(exercise, executionType: executionType)
    }

    /// Sides are only meaningful for reps/weight tracking — a max-hold set has no
    /// left/right split in this app.
    var isTrackingSides: Bool {
        tracksSides && trackingMode == .repsWeight
    }

    /// Slots to fill for this entry: one per set, doubled when tracking sides.
    var totalSetSlots: Int {
        targetSets * (isTrackingSides ? 2 : 1)
    }
}
