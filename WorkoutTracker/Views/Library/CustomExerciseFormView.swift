import SwiftUI
import SwiftData

struct CustomExerciseFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \ExerciseCategory.name) private var allCategories: [ExerciseCategory]

    @State private var name = ""
    @State private var notes = ""
    @State private var equipmentID: UUID?
    @State private var selectedMuscleIDs: Set<UUID> = []
    @State private var selectedCategoryNames: Set<String> = []
    @State private var createdExercise: Exercise?

    var body: some View {
        NavigationStack {
            if let createdExercise {
                PostSaveSyncPrompt(
                    itemName: createdExercise.name,
                    model: createdExercise,
                    syncSingle: { try? await SyncEngine.shared.syncSingle(exercise: createdExercise) },
                    onDone: { dismiss() }
                )
            } else {
                Form {
                    Section("Name") {
                        TextField("e.g. Cable Chest Fly", text: $name)
                    }

                    Section("Equipment") {
                        Picker("Equipment", selection: $equipmentID) {
                            Text("Bodyweight / None").tag(UUID?.none)
                            ForEach(allEquipment) { equipment in
                                Text(equipment.name).tag(Optional(equipment.id))
                            }
                        }
                    }

                    Section("Muscles") {
                        ForEach(allMuscles) { muscle in
                            Toggle(muscle.name, isOn: Binding(
                                get: { selectedMuscleIDs.contains(muscle.id) },
                                set: { isOn in
                                    if isOn { selectedMuscleIDs.insert(muscle.id) }
                                    else { selectedMuscleIDs.remove(muscle.id) }
                                }
                            ))
                        }
                    }

                    Section("Categories") {
                        ForEach(allCategories) { category in
                            Toggle(category.name.capitalized, isOn: Binding(
                                get: { selectedCategoryNames.contains(category.name) },
                                set: { isOn in
                                    if isOn { selectedCategoryNames.insert(category.name) }
                                    else { selectedCategoryNames.remove(category.name) }
                                }
                            ))
                        }
                    }

                    Section("Notes") {
                        TextField("Optional notes", text: $notes, axis: .vertical)
                    }
                }
                .themedListBackground()
                .navigationTitle("New Exercise")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        let equipment = allEquipment.first { $0.id == equipmentID }
        let categories = allCategories.filter { selectedCategoryNames.contains($0.name) }
        let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: Array(selectedCategoryNames))
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            iconSymbolName: symbol,
            isCustom: true,
            isFavorited: true,
            equipment: equipment
        )
        exercise.muscles = allMuscles.filter { selectedMuscleIDs.contains($0.id) }
        exercise.categories = categories
        context.insert(exercise)
        try? context.save()
        createdExercise = exercise
    }
}
