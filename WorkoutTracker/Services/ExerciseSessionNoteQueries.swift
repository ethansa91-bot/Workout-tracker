import Foundation
import SwiftData

/// Historical note lookups for the in-session "last note" preview and its expandable
/// history — same "excluding this session" shape as `SetLogQueries`.
enum ExerciseSessionNoteQueries {
    /// Every note for this exercise from other sessions, oldest to newest — the most
    /// recent one (`.last`) is the "last note" preview shown during a workout.
    static func pastNotes(for exercise: Exercise, excluding session: WorkoutSession, context: ModelContext) -> [ExerciseSessionNote] {
        let exerciseID = exercise.id
        let sessionID = session.id
        let descriptor = FetchDescriptor<ExerciseSessionNote>(
            predicate: #Predicate { note in note.exercise?.id == exerciseID && note.session?.id != sessionID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
