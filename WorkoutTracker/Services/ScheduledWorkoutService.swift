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

    /// Whether a scheduled workout was actually done: its workout has a finished
    /// session on the same day.
    ///
    /// Inferred, not stored — the schedule was built around dates alone, with no link
    /// from an occurrence to the session that fulfilled it. So a spontaneous session on
    /// a day the same workout happened to be scheduled counts as completing it, and one
    /// done a day late doesn't count at all. Accurate enough for a 7-day tally, and it
    /// works on history recorded before this existed.
    static func isCompleted(_ occurrence: ScheduledWorkout) -> Bool {
        guard let workout = occurrence.workout else { return false }
        return workout.sessions.contains { session in
            session.deletedAt == nil
                && session.status == .finished
                && Calendar.current.isDate(session.startedAt, inSameDayAs: occurrence.date)
        }
    }
}
