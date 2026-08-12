import Foundation
import SwiftData

/// One-time bulk import of exercises from the user's own workout log, all marked as
/// favorites. Dedup is exact, case-insensitive name match against the existing
/// catalog: a match just gets favorited in place, a miss becomes a new custom
/// exercise (equipment intentionally left unset — added later by hand).
enum FavoriteExercisesImport {
    private static let importedFlagKey = "import.favoriteExercisesV1"

    private struct Entry {
        let name: String
        let muscleName: String
        let categoryName: String
        let notes: String?
    }

    private static let entries: [Entry] = [
        // Abs
        Entry(name: "Ab Wheel Rollout", muscleName: "Abs", categoryName: "calisthenics", notes: nil),
        Entry(name: "Hollow Body Hold (Banana Hold)", muscleName: "Abs", categoryName: "calisthenics", notes: "On back, feet and shoulders lifted, arched position. Hold."),
        Entry(name: "Banana Kicks", muscleName: "Abs", categoryName: "calisthenics", notes: "Arched hollow position, feet and shoulders off floor. Kick one leg up and down."),
        Entry(name: "Basic Crunch", muscleName: "Abs", categoryName: "calisthenics", notes: "Knees bent, feet flat. Crunch shoulders toward knees."),
        Entry(name: "Crunch Pulse (Top-Range)", muscleName: "Abs", categoryName: "calisthenics", notes: "Knees bent, feet flat. Small, fast pulses at top of crunch."),
        Entry(name: "Crunch Hold", muscleName: "Abs", categoryName: "calisthenics", notes: "Knees bent, feet flat. Hold at top of crunch."),
        Entry(name: "Bent-Knee Crunch, Basic (Legs at 90°)", muscleName: "Abs", categoryName: "calisthenics", notes: "Feet up, knees bent 90°. Crunch toward knees."),
        Entry(name: "Bent-Knee Crunch, Pulse (Legs at 90°)", muscleName: "Abs", categoryName: "calisthenics", notes: "Feet up, knees bent 90°. Small, fast pulses at top."),
        Entry(name: "Bent-Knee Crunch, Hold (Legs at 90°)", muscleName: "Abs", categoryName: "calisthenics", notes: "Feet up, knees bent 90°. Hold at top."),
        Entry(name: "Flat Leg Crunch, Basic (Straight Relaxed Legs)", muscleName: "Abs", categoryName: "calisthenics", notes: "Legs straight and relaxed on floor. Short-range crunch, upper abs focus."),
        Entry(name: "Flat Leg Crunch, Pulse (Straight Relaxed Legs)", muscleName: "Abs", categoryName: "calisthenics", notes: "Legs straight and relaxed on floor. Small, fast pulses at top."),
        Entry(name: "Flat Leg Crunch, Hold (Straight Relaxed Legs)", muscleName: "Abs", categoryName: "calisthenics", notes: "Legs straight and relaxed on floor. Hold at top."),
        Entry(name: "Straight Leg Raised Crunch, Basic", muscleName: "Abs", categoryName: "calisthenics", notes: "Legs straight, raised toward ceiling. Crunch toward feet."),
        Entry(name: "Straight Leg Raised Crunch, Pulse", muscleName: "Abs", categoryName: "calisthenics", notes: "Legs straight, raised toward ceiling. Small, fast pulses at top."),
        Entry(name: "Straight Leg Raised Crunch, Hold", muscleName: "Abs", categoryName: "calisthenics", notes: "Legs straight, raised toward ceiling. Hold at top."),
        Entry(name: "Figure-4 Crunch", muscleName: "Abs", categoryName: "calisthenics", notes: "One leg bent in figure-4, other leg straight. Crunch toward straight leg."),
        Entry(name: "X Crunch (Opposite Arm/Leg)", muscleName: "Abs", categoryName: "calisthenics", notes: "Arms and legs extended in X. Bring one arm and opposite leg up to meet, alternate sides."),
        Entry(name: "Hanging Hollow Hold (Arched, Still)", muscleName: "Abs", categoryName: "calisthenics", notes: "Hang from bar, hold body still in arched position."),
        Entry(name: "Hanging Alternating Knee Raise", muscleName: "Abs", categoryName: "calisthenics", notes: "Hang from bar, raise knees one at a time, alternating."),
        Entry(name: "Hanging Double Knee Raise", muscleName: "Abs", categoryName: "calisthenics", notes: "Hang from bar, raise both knees together."),
        Entry(name: "Hanging Straight Leg Raise", muscleName: "Abs", categoryName: "calisthenics", notes: "Hang from bar, raise a straight leg in front."),
        Entry(name: "Hanging Around the World", muscleName: "Abs", categoryName: "calisthenics", notes: "Hang from bar, sweep a straight leg side to side in a circle."),

        // Legs
        Entry(name: "TRX Fallback (Nordic-Style Hamstring Fallback)", muscleName: "Hamstrings", categoryName: "strength", notes: "Kneeling facing TRX, lean back slowly controlling the fall, pull back up with TRX."),
        Entry(name: "TRX Hip Bridge Curl", muscleName: "Hamstrings", categoryName: "strength", notes: "Feet in TRX straps, lift hips into bridge, curl feet in toward body."),
        Entry(name: "Side Plank Bench Leg Pump", muscleName: "Outer Thighs", categoryName: "calisthenics", notes: "Side plank, one foot on bench, other leg straight underneath. Pump underneath leg up and down."),
        Entry(name: "Resistance Band Lunge (Inward Pull)", muscleName: "Inner Thighs", categoryName: "strength", notes: "Lunge with band around front leg, pulling inward."),
        Entry(name: "Resistance Band Lunge (Outward Pull)", muscleName: "Outer Thighs", categoryName: "strength", notes: "Lunge with band around front leg, pulling outward."),
        Entry(name: "Weighted Lunge", muscleName: "Quad", categoryName: "strength", notes: "Lunge holding a dumbbell or wearing a weight vest."),
        Entry(name: "Barbell Back Squat", muscleName: "Quad", categoryName: "strength", notes: nil),
        Entry(name: "Barbell Sumo Squat", muscleName: "Inner Thighs", categoryName: "strength", notes: nil),

        // Butt
        Entry(name: "Donkey Kick Pulse (Bent Knee Up/Down)", muscleName: "Glutes", categoryName: "calisthenics", notes: "All fours, knee bent, kick leg straight up and down."),
        Entry(name: "Fire Hydrant (Bent Knee Sideways)", muscleName: "Glutes", categoryName: "calisthenics", notes: "All fours, knee bent, lift leg out to the side."),
        Entry(name: "Fire Hydrant to Extension", muscleName: "Glutes", categoryName: "calisthenics", notes: "All fours, lift bent knee to side, extend leg straight, return to bent knee down."),

        // Bicep
        Entry(name: "TRX Bicep Curl", muscleName: "Biceps", categoryName: "strength", notes: "Facing TRX, lean back arms extended, curl by bending elbows."),
        Entry(name: "TRX Cross Bicep Curl", muscleName: "Biceps", categoryName: "strength", notes: "Facing TRX, lean back, bend elbows crossing hands toward chest."),
        Entry(name: "Dumbbell Concentration Curl", muscleName: "Biceps", categoryName: "strength", notes: "Seated, elbow on knee, curl to full extension, one arm at a time."),
        Entry(name: "Standing Dumbbell Curl", muscleName: "Biceps", categoryName: "strength", notes: "Standing, curl dumbbells up."),
        Entry(name: "Incline Dumbbell Curl (45°)", muscleName: "Biceps", categoryName: "strength", notes: "45° incline bench, dumbbell each hand, lower to full extension, curl up."),
        Entry(name: "Hammer Curl", muscleName: "Biceps", categoryName: "strength", notes: "Neutral (hammer) grip, curl dumbbells up."),
        Entry(name: "Dumbbell Preacher Curl", muscleName: "Biceps", categoryName: "strength", notes: "Preacher bench, curl one dumbbell at a time."),
        Entry(name: "EZ Bar Preacher Curl", muscleName: "Biceps", categoryName: "strength", notes: "Preacher bench, curl EZ bar."),

        // Back
        Entry(name: "TRX Y Raise", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Facing TRX, extend arms from front up to Y position."),
        Entry(name: "TRX I Raise", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Facing TRX, extend arms straight overhead to I position."),
        Entry(name: "TRX Row", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Facing TRX, pull body toward handles, scapula engaged, elbows bent."),
        Entry(name: "Resistance Band Pull (Scapula Activation)", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Pull resistance band toward you, scapula engaged."),
        Entry(name: "Ring Row (Inverted Row)", muscleName: "Lats/Upper Back", categoryName: "calisthenics", notes: "Rings at knee height, legs extended, body flat. Pull body up."),
        Entry(name: "Single-Arm Dumbbell Row (3-Point Stance)", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "One hand on bench, dumbbell in other hand. Pull weight to side, lower to full extension."),
        Entry(name: "Incline Reverse Fly", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Face-down 45° incline bench. Straight arms open out to sides."),
        Entry(name: "Bent-Over Reverse Fly (Standing)", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Bend forward 90° at hips. Straight arms open out to sides."),
        Entry(name: "Barbell Row", muscleName: "Lats/Upper Back", categoryName: "strength", notes: "Bend forward 90° at hips. Pull barbell from full extension to torso."),
        Entry(name: "Ring Chin-Up", muscleName: "Lats/Upper Back", categoryName: "calisthenics", notes: nil),
        Entry(name: "Ring Pull-Up", muscleName: "Lats/Upper Back", categoryName: "calisthenics", notes: nil),

        // Traps
        Entry(name: "Dumbbell Rolling Shrug (Forward Rotation)", muscleName: "Traps", categoryName: "strength", notes: "Dumbbell each hand, shrug up, rotate forward."),
        Entry(name: "Dumbbell Rolling Shrug (Backward Rotation)", muscleName: "Traps", categoryName: "strength", notes: "Dumbbell each hand, shrug up, rotate backward."),

        // Triceps
        Entry(name: "TRX Triceps Extension", muscleName: "Triceps", categoryName: "strength", notes: "Facing away from TRX, bend elbows, push back to extend arms. Lean forward for difficulty."),
        Entry(name: "Bench Dips", muscleName: "Triceps", categoryName: "calisthenics", notes: "Support on bench or box behind you, lower and raise body with triceps."),
        Entry(name: "Seated Two-Hand Dumbbell Overhead Triceps Extension", muscleName: "Triceps", categoryName: "strength", notes: "Seated, one dumbbell held with both hands overhead, lower behind head, press up."),
        Entry(name: "Lying Dumbbell Triceps Extension (Cross-Face)", muscleName: "Triceps", categoryName: "strength", notes: "Lying down, lower dumbbell across face, extend back up."),
        Entry(name: "Dumbbell Skull Crusher (Hammer Grip)", muscleName: "Triceps", categoryName: "strength", notes: "Neutral grip, two dumbbells, lower toward head elbows back, press up."),
        Entry(name: "Triceps Kickback (3-Point Stance)", muscleName: "Triceps", categoryName: "strength", notes: "One hand on bench, dumbbell in other hand. Push weight back with triceps."),
        Entry(name: "Incline Lying Triceps Extension", muscleName: "Triceps", categoryName: "strength", notes: "Face-down on incline bench. Bend elbows, extend arms fully."),
        Entry(name: "EZ Bar Skull Crusher", muscleName: "Triceps", categoryName: "strength", notes: "Lying on bench, lower EZ bar toward head elbows back, press up."),
        Entry(name: "Seated EZ Bar Triceps Extension", muscleName: "Triceps", categoryName: "strength", notes: "Seated, lower EZ bar behind head elbows back, press up."),

        // Shoulder
        Entry(name: "Ring Support Hold (Straight-Arm)", muscleName: "Shoulder", categoryName: "calisthenics", notes: "Straight-arm ring support, hands rotated outward. Hold for time."),
        Entry(name: "Ring T-Hold (Open/Close)", muscleName: "Shoulder", categoryName: "calisthenics", notes: "From ring support, open arms out to sides into T, then close. Repeat."),
        Entry(name: "Rotator Cuff Prevention Raise (Kneeling)", muscleName: "Shoulder", categoryName: "physio", notes: "Kneeling, elbow on knee. Raise and lower arm rotating shoulder."),
        Entry(name: "Dumbbell Shoulder Press", muscleName: "Shoulder", categoryName: "strength", notes: "Seated 90° bench, press dumbbells from ear height to full extension."),
        Entry(name: "Seated Dumbbell Shoulder Press (Rotated Grip)", muscleName: "Shoulder", categoryName: "strength", notes: "Seated 90° bench, palms rotated facing you, press from ear height to full extension."),
        Entry(name: "Dumbbell Lateral Raise", muscleName: "Shoulder", categoryName: "strength", notes: "Standing, raise both dumbbells to sides, up to shoulder height."),
        Entry(name: "Dumbbell Front Raise", muscleName: "Shoulder", categoryName: "strength", notes: "Standing, raise one dumbbell in front at a time, up to shoulder height."),
        Entry(name: "Arnold Press", muscleName: "Shoulder", categoryName: "strength", notes: "Seated 90° bench, dumbbells in front of face, press up rotating palms outward to full extension."),
        Entry(name: "Barbell Overhead Press", muscleName: "Shoulder", categoryName: "strength", notes: nil),

        // Pecs
        Entry(name: "Dumbbell Bench Press", muscleName: "Pectoral", categoryName: "strength", notes: "Flat bench, press dumbbells from 90° elbow bend to full extension."),
        Entry(name: "Dumbbell Fly", muscleName: "Pectoral", categoryName: "strength", notes: "Flat bench, arms extended slightly bent, open and close to sides."),
        Entry(name: "Close-Grip Flat Dumbbell Press", muscleName: "Pectoral", categoryName: "strength", notes: "Flat bench, dumbbells touching palms facing each other, lower to chest together, press up."),
        Entry(name: "Incline Dumbbell Press", muscleName: "Pectoral", categoryName: "strength", notes: "45° incline bench, press dumbbells from 90° elbow bend to full extension."),
        Entry(name: "Incline Dumbbell Fly (45°)", muscleName: "Pectoral", categoryName: "strength", notes: "45° incline bench, arms extended slightly bent, open and close to sides."),
        Entry(name: "Decline Dumbbell Press (-30°)", muscleName: "Pectoral", categoryName: "strength", notes: "-30° decline bench, press dumbbells from 90° elbow bend to full extension."),
        Entry(name: "Decline Dumbbell Fly (-30°)", muscleName: "Pectoral", categoryName: "strength", notes: "-30° decline bench, arms extended slightly bent, open and close to sides."),
        Entry(name: "Chest Dip", muscleName: "Pectoral", categoryName: "calisthenics", notes: nil),
    ]

    static func importIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: importedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: importedFlagKey) }

        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var existingByName: [String: Exercise] = [:]
        for exercise in allExercises {
            existingByName[exercise.name.lowercased()] = exercise
        }

        let allMuscles = (try? context.fetch(FetchDescriptor<Muscle>())) ?? []
        let musclesByName = Dictionary(uniqueKeysWithValues: allMuscles.map { ($0.name, $0) })

        let allCategories = (try? context.fetch(FetchDescriptor<ExerciseCategory>())) ?? []
        let categoriesByName = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.name, $0) })

        for entry in entries {
            if let existing = existingByName[entry.name.lowercased()] {
                existing.isFavorited = true
                existing.markDirty()
                continue
            }

            let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: [entry.categoryName])
            let exercise = Exercise(name: entry.name, notes: entry.notes, iconSymbolName: symbol, imageAssetName: ExerciseImageMapping.assetName[entry.name], isCustom: true, isFavorited: true)
            if let muscle = musclesByName[entry.muscleName] {
                exercise.muscles = [muscle]
            }
            if let category = categoriesByName[entry.categoryName] {
                exercise.categories = [category]
            }
            context.insert(exercise)
        }

        try? context.save()
    }
}
