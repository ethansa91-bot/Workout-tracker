import Foundation
import SwiftData

/// One exercise in an EMOM or AMRAP section. Unlike `RepSectionExercise`, there are no
/// per-exercise settings (sets/rest/tracking mode) — every exercise in the section is
/// shown at once and the whole section shares a single timer.
@Model
final class SectionExerciseEntry: SyncableModel, Orderable {
    var id: UUID = UUID()
    var section: WorkoutSection?
    var sortOrder: Int = 0
    var exercise: Exercise?
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(id: UUID = UUID(), section: WorkoutSection? = nil, sortOrder: Int, exercise: Exercise? = nil) {
        self.id = id
        self.section = section
        self.sortOrder = sortOrder
        self.exercise = exercise
        self.updatedAt = .now
        self.deletedAt = nil
    }
}
