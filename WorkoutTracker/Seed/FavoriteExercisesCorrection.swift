import Foundation
import SwiftData

/// One-time cleanup for the 11 near-duplicates `FavoriteExercisesImport` created
/// before its source data was corrected to point at the existing catalog names
/// directly. Runs once, after `FavoriteExercisesImport.importIfNeeded` — on a
/// device where the import already ran (and thus can't simply be fixed by editing
/// its source data), this merges each duplicate into the exercise the user chose to
/// keep. Safe no-op anywhere the duplicates were never created (a fresh install, or
/// a second run on this device).
enum FavoriteExercisesCorrection {
    private static let correctedFlagKey = "import.favoriteExercisesCorrectionV1"

    private struct Merge {
        let duplicateName: String
        let keepName: String
        let renameKeepTo: String?
    }

    private static let merges: [Merge] = [
        Merge(duplicateName: "Barbell Squat", keepName: "Barbell Back Squat", renameKeepTo: nil),
        Merge(duplicateName: "Standing Dumbbell Lateral Raise", keepName: "Dumbbell Lateral Raise", renameKeepTo: nil),
        Merge(duplicateName: "Alternating Dumbbell Front Raise", keepName: "Dumbbell Front Raise", renameKeepTo: nil),
        Merge(duplicateName: "Seated Dumbbell Shoulder Press", keepName: "Dumbbell Shoulder Press", renameKeepTo: nil),
        Merge(duplicateName: "Barbell Shoulder Press", keepName: "Barbell Overhead Press", renameKeepTo: nil),
        Merge(duplicateName: "Flat Bench Dumbbell Press", keepName: "Dumbbell Bench Press", renameKeepTo: nil),
        Merge(duplicateName: "Flat Bench Dumbbell Fly", keepName: "Dumbbell Fly", renameKeepTo: nil),
        Merge(duplicateName: "Incline Dumbbell Press (45°)", keepName: "Incline Dumbbell Press", renameKeepTo: nil),
        Merge(duplicateName: "Dumbbell Hammer Curl", keepName: "Hammer Curl", renameKeepTo: nil),
        Merge(duplicateName: "Parallel Bar Dips", keepName: "Chest Dip", renameKeepTo: nil),
        Merge(duplicateName: "Bent-Over Barbell Row (90°)", keepName: "Barbell Row", renameKeepTo: nil),
        Merge(duplicateName: "EZ Bar Skull Crusher", keepName: "Skullcrusher", renameKeepTo: "EZ Bar Skull Crusher"),
    ]

    static func correctIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: correctedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: correctedFlagKey) }

        func fetchExercise(named name: String) -> Exercise? {
            var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            return try? context.fetch(descriptor).first
        }

        for merge in merges {
            guard let keep = fetchExercise(named: merge.keepName) else { continue }

            // Delete the duplicate *before* renaming `keep` — renaming first would
            // make `keep` briefly share `merge.duplicateName`'s target name with the
            // still-existing duplicate, and the very next name-based fetch could
            // ambiguously return either row (this actually happened: the Skullcrusher
            // merge deleted the freshly-renamed original instead of the duplicate).
            if let duplicate = fetchExercise(named: merge.duplicateName), duplicate.id != keep.id {
                SyncDeletion.delete(duplicate, context: context)
            }

            keep.isFavorited = true
            if let renameKeepTo = merge.renameKeepTo {
                keep.name = renameKeepTo
            }
            keep.markDirty()
        }

        try? context.save()
    }
}
