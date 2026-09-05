import SwiftUI

/// The show/hide-filters button as it sits in a green header band.
///
/// Just the funnel: Exercises puts the star on the *other* side of its title and Records
/// has no star at all, so bundling the two would give neither screen what it wants. The
/// star is `ExerciseFavoriteFilterButton`, composed separately by whoever needs it.
///
/// The funnel fills when something is actually filtered, so a narrowed list never looks
/// unfiltered just because the strip is closed.
struct HeaderFilterControls: View {
    @Binding var filter: ExerciseFilter
    @Binding var showingFilters: Bool
    /// For a screen that narrows by something `ExerciseFilter` doesn't model — Records
    /// filters by section kind, which isn't an exercise facet. Defaults off, so the
    /// screens without one are unaffected.
    var additionalFilterActive: Bool = false

    /// Whether anything other than the star is narrowing the list — the star has its own
    /// control, so counting it here would keep the funnel lit for a filter already shown.
    private var hasChipFilter: Bool {
        additionalFilterActive
            || !filter.equipmentIDs.isEmpty
            || filter.muscleCategoryName != nil
            || !filter.exerciseCategoryNames.isEmpty
            || filter.muscleID != nil
    }

    var body: some View {
        Button {
            showingFilters.toggle()
        } label: {
                Image(systemName: hasChipFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(showingFilters ? .white.opacity(0.28) : .white.opacity(0.18), in: Circle())
                .overlay(Circle().stroke(.white.opacity(showingFilters ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
