import Foundation
import SwiftData

/// One concrete, dated plan to do a workout — either a one-off (`recurringSchedule`
/// nil) or a single occurrence generated from a `RecurringWorkoutSchedule`. There's
/// no stored "cancelled"/"missed" state: cancelling is `SyncDeletion.delete` (same
/// tombstone mechanism every other removable row in the app uses), and "missed" is
/// always derived by comparing `date` against today at read time.
@Model
final class ScheduledWorkout: SyncableModel {
    var id: UUID = UUID()
    var workout: Workout?
    /// Start-of-day for the scheduled date — no time-of-day component.
    var date: Date = Date.now
    var recurringSchedule: RecurringWorkoutSchedule?
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(id: UUID = UUID(), workout: Workout?, date: Date, recurringSchedule: RecurringWorkoutSchedule? = nil) {
        self.id = id
        self.workout = workout
        self.date = date
        self.recurringSchedule = recurringSchedule
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
