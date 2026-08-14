import Foundation
import SwiftData

enum RepExerciseTrackingMode: String, Codable {
    case repsWeight, maxHoldTime
}

@Model
final class RepBlockExercise: SyncableModel, Orderable {
    @Attribute(.unique) var id: UUID
    var block: WorkoutBlock?
    var sortOrder: Int
    var exercise: Exercise?
    var targetSets: Int
    /// nil falls back to `AppSettings.defaultRestSeconds`.
    var customRestSeconds: Int?
    var trackingModeRaw: String = RepExerciseTrackingMode.repsWeight.rawValue
    /// Only meaningful when `trackingMode == .maxHoldTime` — seconds between
    /// pressing Start and the stopwatch actually beginning to count up.
    var headStartSeconds: Int = 3
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    init(
        id: UUID = UUID(),
        block: WorkoutBlock? = nil,
        sortOrder: Int,
        exercise: Exercise? = nil,
        targetSets: Int,
        customRestSeconds: Int? = nil,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        headStartSeconds: Int = 3
    ) {
        self.id = id
        self.block = block
        self.sortOrder = sortOrder
        self.exercise = exercise
        self.targetSets = targetSets
        self.customRestSeconds = customRestSeconds
        self.trackingModeRaw = trackingMode.rawValue
        self.headStartSeconds = headStartSeconds
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }

    var trackingMode: RepExerciseTrackingMode {
        get { RepExerciseTrackingMode(rawValue: trackingModeRaw) ?? .repsWeight }
        set { trackingModeRaw = newValue.rawValue }
    }
}
