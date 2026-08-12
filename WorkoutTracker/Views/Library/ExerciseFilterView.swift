import SwiftUI
import SwiftData

/// Facets: muscle, muscle category, exercise, exercise category, equipment — the same
/// set the workout builder's exercise search will reuse in Phase 3.
struct ExerciseFilter: Equatable {
    var favoritedOnly = false
    var equipmentID: UUID?
    var muscleCategoryName: String?
    var exerciseCategoryNames: Set<String> = []
    var muscleID: UUID?

    var isEmpty: Bool {
        !favoritedOnly && equipmentID == nil && muscleCategoryName == nil && exerciseCategoryNames.isEmpty && muscleID == nil
    }

    func matches(_ exercise: Exercise) -> Bool {
        if favoritedOnly && !exercise.isFavorited { return false }
        if let equipmentID, exercise.equipment?.id != equipmentID { return false }
        if let muscleID, !exercise.muscles.contains(where: { $0.id == muscleID }) { return false }
        if let muscleCategoryName,
           !exercise.muscles.contains(where: { muscle in muscle.categories.contains { $0.name == muscleCategoryName } }) {
            return false
        }
        if !exerciseCategoryNames.isEmpty {
            let names = Set(exercise.categories.map(\.name))
            if names.isDisjoint(with: exerciseCategoryNames) { return false }
        }
        return true
    }
}

struct ExerciseFilterView: View {
    @Binding var filter: ExerciseFilter
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \MuscleCategory.name) private var muscleCategories: [MuscleCategory]
    @Query(sort: \ExerciseCategory.name) private var exerciseCategories: [ExerciseCategory]
    @Query(sort: \Muscle.name) private var muscles: [Muscle]

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Favorites only", isOn: $filter.favoritedOnly)

                Section("Equipment") {
                    Picker("Equipment", selection: $filter.equipmentID) {
                        Text("Any").tag(UUID?.none)
                        ForEach(allEquipment) { equipment in
                            Text(equipment.name).tag(Optional(equipment.id))
                        }
                    }
                }

                Section("Muscle category") {
                    Picker("Muscle category", selection: $filter.muscleCategoryName) {
                        Text("Any").tag(String?.none)
                        ForEach(muscleCategories) { category in
                            Text(category.name.capitalized).tag(Optional(category.name))
                        }
                    }
                }

                Section("Muscle") {
                    Picker("Muscle", selection: $filter.muscleID) {
                        Text("Any").tag(UUID?.none)
                        ForEach(muscles) { muscle in
                            Text(muscle.name).tag(Optional(muscle.id))
                        }
                    }
                }

                Section("Exercise categories") {
                    ForEach(exerciseCategories) { category in
                        Toggle(category.name.capitalized, isOn: Binding(
                            get: { filter.exerciseCategoryNames.contains(category.name) },
                            set: { isOn in
                                if isOn { filter.exerciseCategoryNames.insert(category.name) }
                                else { filter.exerciseCategoryNames.remove(category.name) }
                            }
                        ))
                    }
                }
            }
            .themedListBackground()
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = ExerciseFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
