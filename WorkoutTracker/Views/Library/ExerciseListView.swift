import SwiftUI
import SwiftData

struct ExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var filter = ExerciseFilter()
    @State private var showingCreateSheet = false

    private var filtered: [Exercise] {
        allExercises.filter { exercise in
            exercise.deletedAt == nil
                && (searchText.isEmpty
                    || exercise.name.localizedCaseInsensitiveContains(searchText)
                    || (exercise.label?.localizedCaseInsensitiveContains(searchText) ?? false))
                && filter.matches(exercise)
        }
    }

    var body: some View {
        List {
            ExerciseQuickFilterView(filter: $filter)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            ForEach(filtered) { exercise in
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    exerciseRow(exercise)
                }
            }
        }
        .themedListBackground()
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CustomExerciseFormView()
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: exercise.iconSymbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                if !exercise.equipmentItems.isEmpty {
                    Text(exercise.equipmentItems.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                exercise.isFavorited.toggle()
                exercise.markDirty()
                try? context.save()
            } label: {
                Image(systemName: exercise.isFavorited ? "star.fill" : "star")
                    .foregroundStyle(exercise.isFavorited ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
