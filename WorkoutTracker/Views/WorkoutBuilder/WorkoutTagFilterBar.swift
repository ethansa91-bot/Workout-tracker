import SwiftUI
import SwiftData

/// Which tags a list is narrowed to. A plain value with `isEmpty` and a `matches`, the same
/// shape as `ExerciseFilter` — the list owns it as `@State` and applies it itself.
struct WorkoutTagFilter: Equatable {
    var tagIDs: Set<UUID> = []

    var isEmpty: Bool { tagIDs.isEmpty }

    /// Matches **any** selected tag, not all of them. Tags are how you narrow a list to a
    /// rough area ("push, upper"), and requiring every one of them would make each extra
    /// tap return fewer results until none matched — the opposite of what tapping a second
    /// tag feels like it should do.
    func matches(_ tags: [WorkoutTag]) -> Bool {
        guard !isEmpty else { return true }
        return !Set(tags.map(\.id)).isDisjoint(with: tagIDs)
    }
}

/// The always-visible chip row that drives a `WorkoutTagFilter`, shared by the workout
/// list, templates, the archive and history.
///
/// Hides itself entirely when no tags exist — an empty filter strip above an unfiltered
/// list is a control that does nothing, and every one of these screens managed without one
/// until tags existed.
struct WorkoutTagFilterBar: View {
    @Binding var filter: WorkoutTagFilter

    @Query(filter: #Predicate<WorkoutTag> { $0.deletedAt == nil }, sort: \WorkoutTag.name)
    private var allTags: [WorkoutTag]

    var body: some View {
        if !allTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allTags) { tag in
                        SelectableChip(
                            icon: "tag",
                            title: tag.name,
                            isSelected: filter.tagIDs.contains(tag.id),
                            tint: .appStepBlue
                        ) {
                            toggle(tag)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
            }
            // A tag deleted from the tag sheet leaves its id behind in whatever filter was
            // narrowing a list by it — and with no chip left to un-toggle, that list stays
            // silently narrowed with nothing on screen explaining why. Pruned here rather
            // than at each of the three hosts, because this is the only view that knows
            // which tags still exist.
            .onChange(of: allTags.map(\.id)) { _, live in
                filter.tagIDs.formIntersection(live)
            }
        }
    }

    private func toggle(_ tag: WorkoutTag) {
        if filter.tagIDs.contains(tag.id) {
            filter.tagIDs.remove(tag.id)
        } else {
            filter.tagIDs.insert(tag.id)
        }
    }
}
