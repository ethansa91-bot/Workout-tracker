import SwiftUI
import SwiftData

/// Inline, always-visible quick filters for every `ExerciseFilter` facet except
/// equipment: a favorite-star toggle + a multi-select row of exercise-category
/// chips, then a single-select row of muscle-category chips and, once one is
/// selected, a second row of that category's muscles. All bind directly to the
/// same `ExerciseFilter` used to filter the list.
struct ExerciseQuickFilterView: View {
    @Binding var filter: ExerciseFilter

    @Query(sort: \ExerciseCategory.name) private var exerciseCategories: [ExerciseCategory]
    @Query(sort: \MuscleCategory.name) private var muscleCategories: [MuscleCategory]
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]

    private var musclesInSelectedCategory: [Muscle] {
        guard let categoryName = filter.muscleCategoryName else { return [] }
        return allMuscles.filter { muscle in muscle.categories.contains { $0.name == categoryName } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    filter.favoritedOnly.toggle()
                } label: {
                    Image(systemName: filter.favoritedOnly ? "star.fill" : "star")
                        .foregroundStyle(filter.favoritedOnly ? Color.yellow : Color.secondary)
                        .font(.body)
                        .frame(width: 32, height: 32)
                        .background(Color.appSurface, in: Circle())
                        .overlay(Circle().stroke(filter.favoritedOnly ? Color.clear : Color.appHairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading)

                chipRow(exerciseCategories, applyLeadingPadding: false) { category in
                    chip(
                        title: category.name.capitalized,
                        isSelected: filter.exerciseCategoryNames.contains(category.name),
                        tint: Color.appRust
                    ) {
                        toggleExerciseCategory(category.name)
                    }
                }
            }

            chipRow(muscleCategories) { category in
                chip(
                    title: category.name.capitalized,
                    isSelected: filter.muscleCategoryName == category.name,
                    tint: Color.appAccent
                ) {
                    selectMuscleCategory(category.name)
                }
            }

            if filter.muscleCategoryName != nil {
                chipRow(musclesInSelectedCategory) { muscle in
                    chip(
                        title: muscle.name,
                        isSelected: filter.muscleID == muscle.id,
                        tint: Color.appAccent
                    ) {
                        selectMuscle(muscle.id)
                    }
                }
            }
        }
        .padding(.top, 8)
        .animation(.default, value: filter.muscleCategoryName)
    }

    private func chipRow<Item: Identifiable, Content: View>(
        _ items: [Item],
        applyLeadingPadding: Bool = true,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    content(item)
                }
            }
            .padding(.leading, applyLeadingPadding ? 16 : 0)
            .padding(.trailing, 16)
        }
    }

    /// `tint` separates exercise-category chips from muscle-category/muscle chips
    /// (rust vs. accent green) at rest too, not just when selected — an unselected
    /// chip gets a faint tint wash + tinted text/border instead of the same neutral
    /// gray every facet used to share, so the two rows read as different groups
    /// even before you've tapped anything.
    private func chip(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : tint)
                .background(isSelected ? tint : tint.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : tint.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleExerciseCategory(_ name: String) {
        if filter.exerciseCategoryNames.contains(name) {
            filter.exerciseCategoryNames.remove(name)
        } else {
            filter.exerciseCategoryNames.insert(name)
        }
    }

    private func selectMuscleCategory(_ name: String) {
        filter.muscleCategoryName = (filter.muscleCategoryName == name) ? nil : name
        filter.muscleID = nil
    }

    private func selectMuscle(_ id: UUID) {
        filter.muscleID = (filter.muscleID == id) ? nil : id
    }
}
