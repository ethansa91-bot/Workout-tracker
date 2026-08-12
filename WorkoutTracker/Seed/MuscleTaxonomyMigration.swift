import Foundation
import SwiftData

/// One-time local migration from the old 28-muscle/5-category taxonomy to the new,
/// simplified 17-muscle/3-category one. Runs once per device, after
/// `SeedDataLoader.seedIfNeeded` — a fresh install seeds the new taxonomy directly via
/// `muscles.json`/`SeedDataLoader`, so this is a no-op there; it only does real work on
/// a device that already has the old data on disk (and possibly already synced).
///
/// Deletion goes through `SyncDeletion.delete` (soft tombstone if previously synced),
/// and the new rows are plain locally-created dirty rows — both flow through the
/// existing sync machinery (including `JoinSync`'s replace-all-associations pass) on
/// the next "Sync," so no manual Supabase SQL is needed for this migration.
enum MuscleTaxonomyMigration {
    private static let migratedFlagKey = "migration.muscleTaxonomyV1"

    /// Old muscle name -> new muscle name. Every name ever seeded under the old
    /// taxonomy must appear here.
    private static let nameMapping: [String: String] = [
        "Trapezius": "Traps",
        "Front Deltoids": "Shoulder",
        "Lateral Deltoids": "Shoulder",
        "Rear Deltoids": "Shoulder",
        "Rotator Cuff": "Shoulder",
        "Pectoralis Major": "Pectoral",
        "Latissimus Dorsi": "Lats/Upper Back",
        "Rhomboids": "Lats/Upper Back",
        "Serratus Anterior": "Lats/Upper Back",
        "Erector Spinae": "Lower Back",
        "Biceps Brachii": "Biceps",
        "Triceps Brachii": "Triceps",
        "Forearm Flexors": "Forearm",
        "Forearm Extensors": "Forearm",
        "Sternocleidomastoid": "Traps",
        "Rectus Abdominis": "Abs",
        "Transverse Abdominis": "Abs",
        "Obliques": "Oblique",
        "Hip Flexors": "Hip Flexors",
        "Gluteus Maximus": "Glutes",
        "Gluteus Medius": "Glutes",
        "Quadriceps": "Quad",
        "Hamstrings": "Hamstrings",
        "Adductors": "Inner Thighs",
        "Abductors": "Outer Thighs",
        "Gastrocnemius": "Calves",
        "Soleus": "Calves",
        "Tibialis Anterior": "Calves",
    ]

    /// New muscle name -> the single category it belongs to.
    private static let newMuscleCategories: [String: String] = [
        "Forearm": "upperBody", "Biceps": "upperBody", "Triceps": "upperBody",
        "Shoulder": "upperBody", "Traps": "upperBody", "Lats/Upper Back": "upperBody",
        "Pectoral": "upperBody",
        "Lower Back": "core", "Abs": "core", "Oblique": "core", "Hip Flexors": "core",
        "Glutes": "lowerBody", "Quad": "lowerBody", "Outer Thighs": "lowerBody",
        "Inner Thighs": "lowerBody", "Hamstrings": "lowerBody", "Calves": "lowerBody",
    ]

    private static let obsoleteCategoryNames = ["legs", "arms"]

    static func migrateIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        let allMuscles = (try? context.fetch(FetchDescriptor<Muscle>())) ?? []
        let oldMuscles = allMuscles.filter { nameMapping[$0.name] != nil }
        guard !oldMuscles.isEmpty else { return }

        let allCategories = (try? context.fetch(FetchDescriptor<MuscleCategory>())) ?? []
        var categoriesByName = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.name, $0) })

        func category(named name: String) -> MuscleCategory {
            if let existing = categoriesByName[name] { return existing }
            let category = MuscleCategory(id: SeedIdentity.uuid("muscleCategory", name), name: name)
            context.insert(category)
            categoriesByName[name] = category
            return category
        }

        var newMusclesByName: [String: Muscle] = [:]
        func newMuscle(named name: String) -> Muscle {
            if let existing = newMusclesByName[name] { return existing }
            let categoryName = newMuscleCategories[name] ?? "upperBody"
            let muscle = Muscle(
                id: SeedIdentity.uuid("muscle", name),
                name: name,
                iconSymbolName: SeedDataLoader.symbol(forMuscleCategories: [categoryName])
            )
            muscle.categories = [category(named: categoryName)]
            context.insert(muscle)
            newMusclesByName[name] = muscle
            return muscle
        }

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            var replaced: [Muscle] = []
            for oldMuscle in exercise.muscles {
                guard let newName = nameMapping[oldMuscle.name] else { continue }
                let muscle = newMuscle(named: newName)
                if !replaced.contains(where: { $0.id == muscle.id }) {
                    replaced.append(muscle)
                }
            }
            if !replaced.isEmpty {
                exercise.muscles = replaced
                exercise.markDirty()
            }
        }

        for muscle in oldMuscles {
            SyncDeletion.delete(muscle, context: context)
        }

        for category in allCategories where obsoleteCategoryNames.contains(category.name) {
            SyncDeletion.delete(category, context: context)
        }

        try? context.save()
    }
}
