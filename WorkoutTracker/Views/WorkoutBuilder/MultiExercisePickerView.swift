import SwiftUI
import SwiftData

/// Multi-select sibling of `ExercisePickerView`: stays open across multiple taps so
/// several exercises can be bulk-added in one pass, then closed with "Done."
struct MultiExercisePickerView: View {
    /// Exercises already in the block, so reopening this picker to add more doesn't
    /// look like a blank slate — shown as an "In workout" marker. The "+" stays fully
    /// active regardless, since adding the same exercise again (to repeat it later in
    /// the block) is intentionally supported.
    var existingExerciseIDs: Set<UUID> = []
    let onDone: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var filter = ExerciseFilter()
    @State private var showingFilters = false
    @State private var selectedExercises: [Exercise] = []

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
                row(exercise)
            }
            .themedListBackground()
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(selectedExercises)
                        dismiss()
                    }
                    .disabled(selectedExercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingFilters) {
                ExerciseFilterView(filter: $filter)
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        let selected = isSelected(exercise)
        let alreadyInBlock = existingExerciseIDs.contains(exercise.id)
        return HStack(spacing: 12) {
            IconBadge(systemName: exercise.iconSymbolName)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                    if alreadyInBlock {
                        StatusPill(text: "In workout", tint: .secondary)
                    }
                }
                if let equipmentName = exercise.equipment?.name {
                    Text(equipmentName).font(.caption).foregroundStyle(.secondary)
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
