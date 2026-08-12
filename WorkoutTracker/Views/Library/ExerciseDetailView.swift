import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                if let imageAssetName = exercise.imageAssetName {
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
                    title: exercise.name,
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

            if let equipmentName = exercise.equipment?.name {
                Section("Equipment") {
                    Text(equipmentName)
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
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
