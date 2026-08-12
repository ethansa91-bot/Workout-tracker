import SwiftUI
import SwiftData

/// Single-exercise picker reusing the same search/filter facets as the Library's
/// exercise browser (muscle, muscle category, exercise category, equipment).
struct ExercisePickerView: View {
    let onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var filter = ExerciseFilter()
    @State private var showingFilters = false

    private var filtered: [Exercise] {
        allExercises.filter { exercise in
            exercise.deletedAt == nil
                && (searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText))
                && filter.matches(exercise)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: exercise.iconSymbolName)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                            if let equipmentName = exercise.equipment?.name {
                                Text(equipmentName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .themedListBackground()
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filter", systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFilters) {
                ExerciseFilterView(filter: $filter)
            }
        }
    }
}
