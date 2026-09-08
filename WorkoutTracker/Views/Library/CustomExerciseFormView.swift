import SwiftUI
import SwiftData

/// Creates a brand-new custom exercise. Editing an exercise already in the library
/// (custom or catalog) happens directly on `ExerciseDetailView` instead — chips there
/// for equipment/muscles/categories, `ExerciseIdentityEditView` for name/label/video/notes.
struct CustomExerciseFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \ExerciseCategory.name) private var allCategories: [ExerciseCategory]
    @Query(filter: #Predicate<ExecutionType> { $0.deletedAt == nil }, sort: \ExecutionType.name)
    private var allExecutionTypes: [ExecutionType]

    @State private var name = ""
    @State private var label = ""
    @State private var notes = ""
    @State private var videoURLText = ""
    @State private var selectedEquipmentIDs: Set<UUID> = []
    @State private var selectedMuscleIDs: Set<UUID> = []
    @State private var selectedCategoryNames: Set<String> = []
    @State private var selectedExecutionTypeIDs: Set<UUID> = []
    @State private var separateRecordsPerExecutionType = false
    @State private var allowsBodyweight = false
    @State private var isOneSided = false

    /// Mirrors `Exercise.weightedEquipment`, but over the form's live selection — the
    /// bodyweight option only means something once weighted equipment is chosen.
    private var hasWeightedEquipment: Bool {
        allEquipment.contains { $0.isWeighted && selectedEquipmentIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Cable Chest Fly", text: $name)
                }

                Section {
                    TextField("e.g. Front squat (heavy)", text: $label)
                } header: {
                    Text("Personal Label")
                } footer: {
                    Text("Optional. Once set, this shows in place of the name everywhere.")
                }

                Section {
                    if YouTubeURL.videoID(from: videoURLText) != nil {
                        YouTubeThumbnailButton(urlString: videoURLText, title: name)
                            .frame(height: 160)
                            .listRowInsets(EdgeInsets())
                    }
                    TextField("YouTube link", text: $videoURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Video")
                } footer: {
                    Text("Paste a YouTube link. Shown as a thumbnail here — tap to play. Auto-plays muted during workouts.")
                }

                Section("Muscles") {
                    chipGrid(allMuscles, tint: .appAccent, title: \.name, isSelected: { selectedMuscleIDs.contains($0.id) }, toggle: toggleMuscle)
                }

                Section("Passive Equipment") {
                    chipGrid(allEquipment.filter { !$0.isWeighted }, tint: .appStepBrown, title: \.name, isSelected: { selectedEquipmentIDs.contains($0.id) }, toggle: toggleEquipment)
                }

                Section {
                    chipGrid(allEquipment.filter { $0.isWeighted }, tint: .appStepBlue, title: \.name, isSelected: { selectedEquipmentIDs.contains($0.id) }, toggle: toggleEquipment)
                } header: {
                    HStack(spacing: 8) {
                        Text("Weighted Equipment")
                        Spacer(minLength: 8)
                        if hasWeightedEquipment {
                            PlainHeaderToggle(title: "Allow bodyweight", isOn: allowsBodyweight) {
                                allowsBodyweight.toggle()
                            }
                        }
                    }
                } footer: {
                    Text("\"Allow bodyweight\" lets a workout offer this exercise unloaded.")
                }

                Section("Categories") {
                    chipGrid(allCategories, tint: .appRust, title: { $0.name.capitalized }, isSelected: { selectedCategoryNames.contains($0.name) }, toggle: toggleCategory)
                }

                ExecutionTypeChipSection(
                    isSelected: { selectedExecutionTypeIDs.contains($0.id) },
                    toggle: toggleExecutionType,
                    onCreate: toggleExecutionType,
                    selectedCount: selectedExecutionTypeIDs.count,
                    separateRecords: $separateRecordsPerExecutionType,
                    usesPlainHeader: true
                )

                Section {
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        SelectableChip(icon: "arrow.left.and.right", title: "One-sided", isSelected: isOneSided, tint: .appStepBrown) {
                            isOneSided.toggle()
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Options")
                } footer: {
                    Text("\"One-sided\" lets a workout log left and right separately.")
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

    private func chipGrid<Item: Identifiable>(
        _ items: [Item],
        tint: Color,
        title: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        toggle: @escaping (Item) -> Void
    ) -> some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(items) { item in
                SelectableChip(title: title(item), isSelected: isSelected(item), tint: tint) {
                    toggle(item)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleMuscle(_ muscle: Muscle) {
        if selectedMuscleIDs.contains(muscle.id) { selectedMuscleIDs.remove(muscle.id) }
        else { selectedMuscleIDs.insert(muscle.id) }
    }

    private func toggleEquipment(_ equipment: Equipment) {
        if selectedEquipmentIDs.contains(equipment.id) { selectedEquipmentIDs.remove(equipment.id) }
        else { selectedEquipmentIDs.insert(equipment.id) }
    }

    private func toggleExecutionType(_ type: ExecutionType) {
        if selectedExecutionTypeIDs.contains(type.id) { selectedExecutionTypeIDs.remove(type.id) }
        else { selectedExecutionTypeIDs.insert(type.id) }
    }

    private func toggleCategory(_ category: ExerciseCategory) {
        if selectedCategoryNames.contains(category.name) { selectedCategoryNames.remove(category.name) }
        else { selectedCategoryNames.insert(category.name) }
    }

    private func save() {
        let equipment = allEquipment.filter { selectedEquipmentIDs.contains($0.id) }
        let muscles = allMuscles.filter { selectedMuscleIDs.contains($0.id) }
        let categories = allCategories.filter { selectedCategoryNames.contains($0.name) }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVideoURL = videoURLText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symbol = IconSymbolMapping.defaultExerciseSymbol(forCategoryNames: Array(selectedCategoryNames))
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            videoURL: trimmedVideoURL.isEmpty ? nil : trimmedVideoURL,
            iconSymbolName: symbol,
            isCustom: true,
            isFavorited: true,
            allowsBodyweight: hasWeightedEquipment && allowsBodyweight,
            isOneSided: isOneSided,
            equipmentItems: equipment
        )
        exercise.muscles = muscles
        exercise.categories = categories
        exercise.executionTypes = allExecutionTypes.filter { selectedExecutionTypeIDs.contains($0.id) }
        // Same guard the toggle's visibility applies: a flag set while only one type was
        // attached, then narrowed to none, would otherwise persist as a dormant true.
        exercise.separateRecordsPerExecutionType = selectedExecutionTypeIDs.count > 1 && separateRecordsPerExecutionType
        context.insert(exercise)
        try? context.save()
        dismiss()
    }
}
