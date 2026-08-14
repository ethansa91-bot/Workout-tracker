import Foundation
import SwiftData

/// Owns creation/rescheduling/cancellation of scheduled workouts. A weekly
/// schedule's occurrences are all generated up front, from today through its
/// (user-chosen) end date — bounded, so no ongoing "keep extending" step is
/// needed after creation.
enum ScheduledWorkoutService {
    static func createOneOff(workout: Workout, date: Date, context: ModelContext) {
        let scheduled = ScheduledWorkout(workout: workout, date: startOfDay(date))
        context.insert(scheduled)
        try? context.save()
    }

    static func createWeekly(workout: Workout, weekdays: [Int], endDate: Date, context: ModelContext) {
        let schedule = RecurringWorkoutSchedule(workout: workout, weekdays: weekdays, endDate: startOfDay(endDate))
        context.insert(schedule)
        generateOccurrences(for: schedule, context: context)
        try? context.save()
    }

    private static func generateOccurrences(for schedule: RecurringWorkoutSchedule, context: ModelContext) {
        let calendar = Calendar.current
        let today = startOfDay(.now)
        guard schedule.endDate >= today else { return }

        let existingDates = Set(
            schedule.occurrences
                .filter { $0.deletedAt == nil }
                .map { calendar.startOfDay(for: $0.date) }
        )

        var date = today
        while date <= schedule.endDate {
            let weekday = calendar.component(.weekday, from: date)
            if schedule.weekdays.contains(weekday) && !existingDates.contains(date) {
                let occurrence = ScheduledWorkout(workout: schedule.workout, date: date, recurringSchedule: schedule)
                context.insert(occurrence)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
    }

    static func move(_ occurrence: ScheduledWorkout, to newDate: Date, context: ModelContext) {
        occurrence.date = startOfDay(newDate)
        occurrence.markDirty()
        try? context.save()
    }

    static func cancel(_ occurrence: ScheduledWorkout, context: ModelContext) {
        SyncDeletion.delete(occurrence, context: context)
        try? context.save()
    }

    /// Cancels the whole series: every not-yet-passed occurrence, plus the
    /// schedule itself. Past occurrences are left alone — nothing retroactive.
    static func cancelSeries(_ schedule: RecurringWorkoutSchedule, context: ModelContext) {
        let today = startOfDay(.now)
        for occurrence in schedule.occurrences where occurrence.deletedAt == nil && occurrence.date >= today {
            SyncDeletion.delete(occurrence, context: context)
        }
        SyncDeletion.delete(schedule, context: context)
        try? context.save()
    }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
