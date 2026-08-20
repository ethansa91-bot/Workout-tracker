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
    var updatedAt: Date = Date.now
    var deletedAt: Date?

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
        tracksSides: Bool = false
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
        self.updatedAt = .now
        self.deletedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
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
