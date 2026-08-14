import Foundation
import SwiftData

/// One-time favoriting pass from the Exercise Reviewer tool's pass over the full
/// 266-exercise wger catalog: the 34 exercises matched to (and merged with, via
/// `WgerCatalogMigration.legacyExerciseMergeMap`) an existing personal exercise, plus
/// 76 new catalog exercises picked as "want to do soon" with no personal match. Must
/// run after `WgerCatalogMigration` so the canonical catalog rows already exist.
enum ExerciseReviewFavoritesImport {
    private static let importedFlagKey = "import.exerciseReviewFavoritesV1"

    private static let favoriteNames: Set<String> = [
        "Ab wheel",
        "Alternating Biceps Curls With Dumbbell",
        "Alternating bicep curls",
        "Alternating dumbbell hammer curl",
        "Arabesque",
        "Axe Hold",
        "Barbell Triceps Extension",
        "Barbell Wrist Curl",
        "Bench Press Narrow Grip",
        "Benchpress Dumbbells",
        "Bent High Pulls",
        "Bent Over Dumbbell Rows",
        "Bent Over Rowing",
        "Bent Over Rowing Reverse",
        "Biceps Curls With Dumbbell",
        "Biceps Curls With SZ-bar",
        "Biceps with TRX",
        "Bulgarian Squat with Dumbbells",
        "Bulgarian split squats left",
        "Bus Drivers",
        "Chin Up",
        "Close-grip Press-ups",
        "Cross-Bench Dumbbell Pullovers",
        "Crunches",
        "Deadlifts",
        "Devil’s Press",
        "Dips",
        "Dips Between Two Benches",
        "Double Leg Calf Raise",
        "Dumbbell Bent Over Face Pull",
        "Dumbbell Front Squat",
        "Dumbbell Goblet Squat",
        "Dumbbell Hex Press",
        "Dumbbell Hip Thrust",
        "Dumbbell Lunges Walking",
        "Dumbbell Rear Lunge",
        "Dumbbell Romanian Deadlift",
        "Dumbbell Side Bend",
        "Dumbbell Side Squat",
        "Dumbbell bicep curl to press",
        "Dumbbell donkey kick",
        "Dumbbell rear delt row",
        "Dumbbell sumo deadlift",
        "Dumbbell wide bicep curls",
        "Face pulls with yellow/green band",
        "Finger Pushup",
        "Floor dips",
        "Fly With Dumbbells",
        "Forearm Curls (underhand grip)",
        "Front Raises",
        "Front Squats",
        "Good Morning",
        "Hammer Curls",
        "High Knee Jumps",
        "Hollow Hold",
        "Hyperextensions",
        "Incline Bench Press - Dumbbell",
        "Incline Bench Reverse Fly",
        "Incline Chest-Supported Dumbbell Row",
        "Inverted Rows",
        "Isometric Squat to Failure",
        "Kettlebell One Legged Deadlift",
        "Knee Raises",
        "Kneeling kickbacks",
        "Lateral Push Off",
        "Lateral Raises",
        "Leg Raises, Lying",
        "Leg raises pull up bar",
        "Lunges",
        "Medicine ball booklet crunch",
        "Medicine ball twist",
        "Overhead Barbell Press",
        "Overhead Triceps Extension",
        "Pike Push Ups",
        "Pistol Squat",
        "Plank",
        "Plank Shoulder Taps",
        "Preacher Curls",
        "Pull-ups",
        "Push Press",
        "Push-Up",
        "Push-Ups | Decline",
        "Rear Delt Raises",
        "Reverse Grip Barbell Curls",
        "Reverse Nordic Curl",
        "Reverse lunges",
        "Russian Twist",
        "Seated Knee Tuck",
        "Seated W Curl",
        "Seated rear delt rise",
        "Shoulder Press, Barbell",
        "Shoulder Press, Dumbbells",
        "Shoulder Raise (Dumbbell)",
        "Shrugs, Dumbbells",
        "Single-Leg Deadlift with Dumbbell",
        "Skullcrusher SZ-bar",
        "Sliding Lateral Lunge",
        "Sloper hanging",
        "Slow Squat",
        "Standing Calf Raises",
        "Step-ups",
        "Suspended crossess",
        "TRX Rows",
        "Triceps Overhead (Dumbbell)",
        "Tuck planche",
        "Upright Row w/ Dumbbells",
        "Upright Row, SZ-bar",
        "Weighted Crunch",
        "Weighted push-ups",
        "rubber band glute kickback",
    ]

    static func importIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: importedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: importedFlagKey) }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var didChange = false

        for exercise in allExercises where favoriteNames.contains(exercise.name) {
            guard !exercise.isFavorited else { continue }
            exercise.isFavorited = true
            exercise.markDirty()
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
