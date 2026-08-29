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
        // Read once, not once per row. `filtered.last?.id` inside the `ForEach` re-ran the
        // whole filter for every row — and `ExerciseFilter.matches` walks each exercise's
        // muscle, equipment and category relationships, so a 180-row catalogue cost ~33k
        // relationship traversals per render.
        let exercises = filtered
        let lastID = exercises.last?.id

        List {
            ForEach(exercises) { exercise in
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    exerciseRow(exercise)
                }
                .fullBleedRow(isLast: exercise.id == lastID)
            }
        }
        .fullBleedList()
        // Band, search and filters ride together above the list rather than scrolling
        // with it — the filters are how you narrow a 180-row catalogue, so losing them
        // on the first swipe made them nearly useless.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PushedTitleBand(title: "Exercises")
                InlineSearchField(prompt: "Search exercises", text: $searchText)
                ExerciseQuickFilterView(filter: $filter)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurface)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.appHairline)
                            .frame(height: 0.5)
                    }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
            // Leading, where the icon badge used to be: the exercise's own symbol was
            // close to arbitrary, and whether it's a favourite is the one per-exercise
            // signal worth seeing first. Fixed width so the filled and hollow glyphs
            // take the same space and every name starts on the same line.
            Button {
                exercise.isFavorited.toggle()
                exercise.markDirty()
                try? context.save()
            } label: {
                Image(systemName: exercise.isFavorited ? "star.fill" : "star")
                    .foregroundStyle(exercise.isFavorited ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
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
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
