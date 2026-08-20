import Foundation
import SwiftData

/// A weekly recurrence pattern ("every Mon/Wed/Fri, through <endDate>") for
/// scheduling a workout. Doesn't represent any single occurrence itself —
/// `ScheduledWorkoutService` materializes every dated `ScheduledWorkout` between
/// today and `endDate` up front when the schedule is created, so each occurrence
/// can individually be opened/moved/cancelled.
@Model
final class RecurringWorkoutSchedule: SyncableModel {
    var id: UUID = UUID()
    var workout: Workout?
    /// `Calendar` weekday values: 1 = Sunday ... 7 = Saturday.
    var weekdays: [Int] = []
    /// Last date occurrences are generated through — user-chosen, either derived
    /// from "N weeks" or picked directly, at creation time.
    var endDate: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ScheduledWorkout.recurringSchedule)
    var occurrencesStorage: [ScheduledWorkout]?
    var occurrences: [ScheduledWorkout] {
        get { occurrencesStorage ?? [] }
        set { occurrencesStorage = newValue }
    }

    init(id: UUID = UUID(), workout: Workout?, weekdays: [Int], endDate: Date) {
        self.id = id
        self.workout = workout
        self.weekdays = weekdays
        self.endDate = endDate
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
