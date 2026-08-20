import Foundation
import SwiftData

/// A free-text note about how an exercise went in a particular session — distinct from
/// `Exercise.notes`, which is a single persistent description, not tied to any session.
/// One note per (exercise, session) pair; editable in place rather than append-only.
/// Local-only for now — no sync fields, unlike the other session models.
@Model
final class ExerciseSessionNote {
    var id: UUID = UUID()
    var session: WorkoutSession?
    var exercise: Exercise?
    var exerciseNameSnapshot: String?
    var text: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil,
        exerciseNameSnapshot: String? = nil,
        text: String = ""
    ) {
        self.id = id
        self.session = session
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Finds the existing note for this (session, exercise) pair, or creates and inserts
    /// a new one — shared by every entry point (in-session, recap) so they never end up
    /// with two notes for the same exercise in the same session.
    static func findOrCreate(session: WorkoutSession, exercise: Exercise, context: ModelContext) -> ExerciseSessionNote {
        if let existing = session.exerciseNotes.first(where: { $0.exercise?.id == exercise.id }) {
            return existing
        }
        let note = ExerciseSessionNote(session: session, exercise: exercise, exerciseNameSnapshot: exercise.displayName)
        context.insert(note)
        return note
    }
}
