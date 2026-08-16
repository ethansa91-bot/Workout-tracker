import SwiftUI
import SwiftData

/// Multi-select sibling of `ExercisePickerView`: stays open across multiple taps so
/// several exercises can be bulk-added in one pass, then closed with "Done."
struct MultiExercisePickerView: View {
    /// Exercises already in the section, so reopening this picker to add more doesn't
    /// look like a blank slate — shown as an "In workout" marker. The "+" stays fully
    /// active regardless, since adding the same exercise again (to repeat it later in
    /// the section) is intentionally supported.
    var existingExerciseIDs: Set<UUID> = []
    let onDone: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var filter = ExerciseFilter(favoritedOnly: true)
    @State private var selectedExercises: [Exercise] = []

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
        NavigationStack {
            VStack(spacing: 0) {
                ExerciseQuickFilterView(filter: $filter)

                List(filtered) { exercise in
                    row(exercise)
                }
                .themedListBackground()
            }
            .background(Color.appBackground)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
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
            .safeAreaInset(edge: .bottom) {
                if !selectedExercises.isEmpty {
                    Button {
                        onDone(selectedExercises)
                        dismiss()
                    } label: {
                        Text("Add \(selectedExercises.count) Exercise\(selectedExercises.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .background(.thickMaterial)
                }
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        let selected = isSelected(exercise)
        let alreadyInSection = existingExerciseIDs.contains(exercise.id)
        return HStack(spacing: 12) {
            IconBadge(systemName: exercise.iconSymbolName)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.displayName)
                    if alreadyInSection {
                        StatusPill(text: "In workout", tint: .secondary)
                    }
                }
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
            Spacer()
            Button {
                toggle(exercise)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func isSelected(_ exercise: Exercise) -> Bool {
        selectedExercises.contains { $0.id == exercise.id }
    }

    private func toggle(_ exercise: Exercise) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }
}
