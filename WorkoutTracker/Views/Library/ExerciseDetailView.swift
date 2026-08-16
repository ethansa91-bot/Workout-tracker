import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @State private var showingEdit = false

    var body: some View {
        List {
            Section {
                if let generatedFileName = exercise.generatedImageFileName, let uiImage = GeneratedExerciseImageStore.load(fileName: generatedFileName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(EdgeInsets())
                        .padding(.bottom, 8)
                } else if let imageAssetName = exercise.imageAssetName {
                    Image(imageAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(EdgeInsets())
                        .padding(.bottom, 8)
                }

                DetailHeader(
                    systemName: exercise.iconSymbolName,
                    title: exercise.displayName,
                    subtitle: exercise.isCustom ? "Custom exercise" : nil
                )

                Toggle("Favorite", isOn: Binding(
                    get: { exercise.isFavorited },
                    set: { newValue in
                        exercise.isFavorited = newValue
                        exercise.markDirty()
                        try? context.save()
                    }
                ))
            }

            if !exercise.equipmentItems.isEmpty {
                Section("Equipment") {
                    ForEach(exercise.equipmentItems.sorted { $0.name < $1.name }) { equipment in
                        Text(equipment.name)
                    }
                }
            }

            if !exercise.muscles.isEmpty {
                Section("Muscles") {
                    ForEach(exercise.muscles.sorted { $0.name < $1.name }) { muscle in
                        Text(muscle.name)
                    }
                }
            }

            if !exercise.categories.isEmpty {
                Section("Categories") {
                    ForEach(exercise.categories.sorted { $0.name < $1.name }) { category in
                        Text(category.name.capitalized)
                    }
                }
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section {
                HStack {
                    Text("Sync")
                    Spacer()
                    SyncButton(isDirty: exercise.isDirty) {
                        try? await SyncEngine.shared.syncSingle(exercise: exercise)
                    }
                }
            }
        }
        .themedListBackground()
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            CustomExerciseFormView(existingExercise: exercise)
        }
    }
}
