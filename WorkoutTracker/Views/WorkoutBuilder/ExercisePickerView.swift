import SwiftUI
import SwiftData

/// Single-exercise picker with inline quick filters (favorites, exercise category,
/// muscle category/muscle) via `ExerciseQuickFilterView`; equipment filtering is
/// only available from the Library's own exercise browser.
struct ExercisePickerView: View {
    var excluding: Set<UUID> = []
    let onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var filter = ExerciseFilter(favoritedOnly: true)

    private var filtered: [Exercise] {
        allExercises.filter { exercise in
            exercise.deletedAt == nil
                && !excluding.contains(exercise.id)
                && (searchText.isEmpty
                    || exercise.name.localizedCaseInsensitiveContains(searchText)
                    || (exercise.label?.localizedCaseInsensitiveContains(searchText) ?? false))
                && filter.matches(exercise)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ExerciseQuickFilterView(filter: $filter)

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
                                Text(exercise.displayName)
                                if exercise.showsSecondaryName {
                                    Text(exercise.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !exercise.equipmentItems.isEmpty {
                                    Text(exercise.equipmentItems.map(\.name).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .themedListBackground()
            }
            .background(Color.appBackground)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}
