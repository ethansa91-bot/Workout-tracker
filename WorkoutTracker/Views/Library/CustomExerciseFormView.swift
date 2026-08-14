import SwiftUI
import SwiftData

/// Shared create/edit form. Pass `existingExercise` to edit an exercise already in the
/// library (custom or catalog) in place; leave it nil to create a brand-new custom one.
/// The canonical catalog `name` can only be set at creation time or for custom
/// exercises — catalog exercises use `label` (a personal nickname) instead, so catalog
/// identity/matching never gets corrupted by an in-place rename.
struct CustomExerciseFormView: View {
    var existingExercise: Exercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \ExerciseCategory.name) private var allCategories: [ExerciseCategory]

    @State private var name = ""
    @State private var label = ""
    @State private var notes = ""
    @State private var selectedEquipmentIDs: Set<UUID> = []
    @State private var selectedMuscleIDs: Set<UUID> = []
    @State private var selectedCategoryNames: Set<String> = []
    @State private var createdExercise: Exercise?

    private var isEditing: Bool { existingExercise != nil }
    private var canEditName: Bool { existingExercise == nil || existingExercise?.isCustom == true }

    init(existingExercise: Exercise? = nil) {
        self.existingExercise = existingExercise
        _name = State(initialValue: existingExercise?.name ?? "")
        _label = State(initialValue: existingExercise?.label ?? "")
        _notes = State(initialValue: existingExercise?.notes ?? "")
        _selectedEquipmentIDs = State(initialValue: Set(existingExercise?.equipmentItems.map(\.id) ?? []))
        _selectedMuscleIDs = State(initialValue: Set(existingExercise?.muscles.map(\.id) ?? []))
        _selectedCategoryNames = State(initialValue: Set(existingExercise?.categories.map(\.name) ?? []))
    }

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
                        if canEditName {
                            TextField("e.g. Cable Chest Fly", text: $name)
                        } else {
                            Text(name).foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        TextField("e.g. Front squat (heavy)", text: $label)
                    } header: {
                        Text("Personal Label")
                    } footer: {
                        Text("Optional. Once set, this shows in place of the name everywhere.")
                    }

                    Section("Passive Equipment") {
                        equipmentToggles(for: allEquipment.filter { !$0.isWeighted })
                    }

                    Section("Weighted Equipment") {
                        equipmentToggles(for: allEquipment.filter { $0.isWeighted })
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
                .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
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

    private func equipmentToggles(for items: [Equipment]) -> some View {
        ForEach(items) { equipment in
            Toggle(equipment.name, isOn: Binding(
                get: { selectedEquipmentIDs.contains(equipment.id) },
                set: { isOn in
                    if isOn { selectedEquipmentIDs.insert(equipment.id) }
                    else { selectedEquipmentIDs.remove(equipment.id) }
                }
            ))
        }
    }

    private func save() {
        let equipment = allEquipment.filter { selectedEquipmentIDs.contains($0.id) }
        let muscles = allMuscles.filter { selectedMuscleIDs.contains($0.id) }
        let categories = allCategories.filter { selectedCategoryNames.contains($0.name) }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingExercise {
            if canEditName {
                existingExercise.name = name.trimmingCharacters(in: .whitespaces)
            }
            existingExercise.label = trimmedLabel.isEmpty ? nil : trimmedLabel
            existingExercise.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existingExercise.equipmentItems = equipment
            existingExercise.muscles = muscles
            existingExercise.categories = categories
            existingExercise.markDirty()
            try? context.save()
            dismiss()
        } else {
            let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: Array(selectedCategoryNames))
            let exercise = Exercise(
                name: name.trimmingCharacters(in: .whitespaces),
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                iconSymbolName: symbol,
                isCustom: true,
                isFavorited: true,
                equipmentItems: equipment
            )
            exercise.muscles = muscles
            exercise.categories = categories
            context.insert(exercise)
            try? context.save()
            createdExercise = exercise
        }
    }
}
