import SwiftUI
import SwiftData

struct MuscleListView: View {
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \MuscleCategory.name) private var categories: [MuscleCategory]

    @State private var searchText = ""
    @State private var selectedCategory: String?

    private var filteredMuscles: [Muscle] {
        allMuscles.filter { muscle in
            muscle.deletedAt == nil
                && (searchText.isEmpty || muscle.name.localizedCaseInsensitiveContains(searchText))
                && (selectedCategory == nil || muscle.categories.contains { $0.name == selectedCategory })
        }
    }

    var body: some View {
        List {
            Picker("Category", selection: $selectedCategory) {
                Text("All").tag(String?.none)
                ForEach(categories) { category in
                    Text(category.name.capitalized).tag(Optional(category.name))
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            ForEach(filteredMuscles) { muscle in
                NavigationLink {
                    MuscleDetailView(muscle: muscle)
                } label: {
                    muscleRow(muscle)
                }
            }
        }
        .themedListBackground()
        .searchable(text: $searchText, prompt: "Search muscles")
        .navigationTitle("Muscles")
    }

    private func muscleRow(_ muscle: Muscle) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: muscle.iconSymbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.name)
                Text(muscle.categories.map { $0.name.capitalized }.sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MuscleDetailView: View {
    let muscle: Muscle

    private var targetingExercises: [Exercise] {
        muscle.exercises.filter { $0.deletedAt == nil }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                DetailHeader(
                    systemName: muscle.iconSymbolName,
                    title: muscle.name,
                    subtitle: muscle.categories.map { $0.name.capitalized }.sorted().joined(separator: ", ")
                )
            }
            Section("Exercises targeting this muscle") {
                if targetingExercises.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                } else {
                    ForEach(targetingExercises) { exercise in
                        HStack(spacing: 12) {
                            IconBadge(systemName: exercise.iconSymbolName, size: 28)
                            Text(exercise.displayName)
                        }
                    }
                }
            }
        }
        .themedListBackground()
        .navigationTitle(muscle.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
