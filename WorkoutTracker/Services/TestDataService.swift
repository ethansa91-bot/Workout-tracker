import Foundation
import SwiftData

/// Dev/QA helper: builds one workout per section type (Rep, Time, EMOM, AMRAP), each
/// with the same 5 exercises chosen to exercise every `ExerciseMediaView` state —
/// picture-only, video-only, both, and neither — so all four session runners can be
/// spot-checked against real media states in a couple of taps instead of hunting for
/// exercises with the right combination by hand.
enum TestDataService {
    private static let workoutNames: [WorkoutSectionType: String] = [
        .rep: "Test — Rep",
        .time: "Test — Time",
        .emom: "Test — EMOM",
        .amrap: "Test — AMRAP",
    ]

    static func generateTestWorkouts(context: ModelContext) throws {
        removePreviousTestWorkouts(context: context)

        let allExercises = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.deletedAt == nil }))
        let exercises = selectTestExercises(from: allExercises)
        guard !exercises.isEmpty else { return }

        try makeRepWorkout(exercises: exercises, context: context)
        try makeTimeWorkout(exercises: exercises, context: context)
        try makeEmomWorkout(exercises: exercises, context: context)
        try makeAmrapWorkout(exercises: exercises, context: context)
    }

    // MARK: - Exercise selection

    private static func hasPicture(_ exercise: Exercise) -> Bool {
        exercise.generatedImageFileName != nil || exercise.imageAssetName != nil
    }

    private static func hasVideo(_ exercise: Exercise) -> Bool {
        exercise.videoURL.flatMap(YouTubeURL.videoID(from:)) != nil
    }

    /// Picture-only, video-only, both, neither, then one more exercise (any) to reach
    /// 5. Falls back to a random not-yet-used exercise whenever a category has no match
    /// — e.g. if nothing in the catalog currently has both a picture and a video.
    private static func selectTestExercises(from pool: [Exercise]) -> [Exercise] {
        var used = Set<UUID>()
        var result: [Exercise] = []

        func pick(matching predicate: (Exercise) -> Bool) {
            let candidates = pool.filter { !used.contains($0.id) }
            let chosen = candidates.first(where: predicate) ?? candidates.randomElement()
            guard let chosen else { return }
            used.insert(chosen.id)
            result.append(chosen)
        }

        pick { hasPicture($0) && !hasVideo($0) }
        pick { hasVideo($0) && !hasPicture($0) }
        pick { hasPicture($0) && hasVideo($0) }
        pick { !hasPicture($0) && !hasVideo($0) }
        pick { _ in true }

        return result
    }

    // MARK: - Workout builders

    private static func makeRepWorkout(exercises: [Exercise], context: ModelContext) throws {
        let workout = WorkoutEditingService.createWorkout(name: workoutNames[.rep]!, context: context)
        let section = try WorkoutEditingService.addSection(to: workout, type: .rep, context: context)
        for exercise in exercises {
            try WorkoutEditingService.addRepExercise(to: section, exercise: exercise, targetSets: 3, customRestSeconds: nil, context: context)
        }
    }

    private static func makeTimeWorkout(exercises: [Exercise], context: ModelContext) throws {
        let workout = WorkoutEditingService.createWorkout(name: workoutNames[.time]!, context: context)
        let section = try WorkoutEditingService.addSection(to: workout, type: .time, context: context)
        for exercise in exercises {
            try WorkoutEditingService.addTimeStep(to: section, stepType: .exercise, exercise: exercise, durationSeconds: 30, context: context)
        }
    }

    private static func makeEmomWorkout(exercises: [Exercise], context: ModelContext) throws {
        let workout = WorkoutEditingService.createWorkout(name: workoutNames[.emom]!, context: context)
        let section = try WorkoutEditingService.addSection(to: workout, type: .emom, context: context)
        for exercise in exercises {
            try WorkoutEditingService.addQuickExercise(to: section, exercise: exercise, context: context)
        }
        // Shorter than the 10-round default — this is for a quick spot-check, not a
        // real workout.
        try WorkoutEditingService.updateEmomRoundCount(section, to: 2, context: context)
    }

    private static func makeAmrapWorkout(exercises: [Exercise], context: ModelContext) throws {
        let workout = WorkoutEditingService.createWorkout(name: workoutNames[.amrap]!, context: context)
        let section = try WorkoutEditingService.addSection(to: workout, type: .amrap, context: context)
        for exercise in exercises {
            try WorkoutEditingService.addQuickExercise(to: section, exercise: exercise, context: context)
        }
        // Shorter than the 12-minute default, same reasoning as the EMOM round count.
        try WorkoutEditingService.updateAmrapDuration(section, to: 60, context: context)
    }

    // MARK: - Cleanup

    /// Removes workouts from a previous run of this same generator (by name) before
    /// creating fresh ones, so repeated taps don't pile up duplicates. Best-effort: a
    /// workout already used in a session can't be deleted (`WorkoutSession`'s delete
    /// rule denies it), so those are just left in place and a new one is added alongside.
    private static func removePreviousTestWorkouts(context: ModelContext) {
        let names = Set(workoutNames.values)
        guard let allWorkouts = try? context.fetch(FetchDescriptor<Workout>()) else { return }
        for workout in allWorkouts where names.contains(workout.name) {
            context.delete(workout)
        }
        try? context.save()
    }
}
