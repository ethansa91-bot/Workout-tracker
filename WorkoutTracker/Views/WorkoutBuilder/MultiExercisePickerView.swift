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
    /// Exercises the list must not offer at all — as opposed to `existingExerciseIDs`,
    /// which only marks. Same meaning the name has on `ExercisePickerView`.
    var excluding: Set<UUID> = []
    /// Why an exercise can't be picked, or nil when it can. A reason rather than a Bool so
    /// the row can say *what* is blocking it — the convention `deleteBlockReason` follows
    /// on the exercise and equipment pages.
    var ineligible: (Exercise) -> String? = { _ in nil }
    let onDone: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var searchText = ""
    @State private var filter: ExerciseFilter
    @State private var selectedExercises: [Exercise] = []
    @State private var flash: FlashMessage.Payload?

    /// Favourites-only suits the builder, where you reach for exercises you actually
    /// train. It is wrong for picking progression rungs — the easier and harder variants
    /// of a movement are exactly the ones you *don't* normally do — so the starting filter
    /// is a parameter rather than a hardcoded default.
    init(
        existingExerciseIDs: Set<UUID> = [],
        excluding: Set<UUID> = [],
        ineligible: @escaping (Exercise) -> String? = { _ in nil },
        initialFilter: ExerciseFilter = ExerciseFilter(favoritedOnly: true),
        onDone: @escaping ([Exercise]) -> Void
    ) {
        self.existingExerciseIDs = existingExerciseIDs
        self.excluding = excluding
        self.ineligible = ineligible
        self.onDone = onDone
        _filter = State(initialValue: initialFilter)
    }

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
                    row(exercise)
                }
                .themedListBackground()
            }
            .background(Color.appBackground)
            // Inside the sheet: a sheet can't leave an overlay behind once it closes, and
            // this answers a tap made while it is open.
            .overlay(alignment: .top) {
                if let flash {
                    FlashMessage(payload: flash) { self.flash = nil }
                }
            }
            .animation(.snappy, value: flash)
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
        let blockReason = ineligible(exercise)
        let isBlocked = blockReason != nil
        return HStack(spacing: 12) {
            IconBadge(systemName: exercise.iconSymbolName, tint: isBlocked ? Color.appInkMuted : .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.displayName)
                        .foregroundStyle(isBlocked ? Color.appInkMuted : Color.primary)
                    if let blockReason {
                        StatusPill(text: blockReason, tint: .secondary)
                    } else if alreadyInSection {
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
                    // Chosen explicitly rather than left to `.disabled`: `.buttonStyle(.plain)`
                    // with an explicit foreground suppresses SwiftUI's own dimming.
                    .foregroundStyle(isBlocked ? Color.appInkMuted : (selected ? Color.green : Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(isBlocked)
        }
        .padding(.vertical, 2)
        // Only on a blocked row, and deliberately not on the others: a row-wide gesture
        // sitting under an enabled Button is how `RestTimerView` lost its taps. A normal
        // row has nothing to say here anyway — its "+" already does the work.
        .modifier(BlockedRowTap(reason: blockReason) { flash = FlashMessage.Payload($0) })
    }

    /// Gives a blocked row something to tap, since only the "+" is a target on a normal
    /// one and a dead row reads as broken rather than as unavailable.
    private struct BlockedRowTap: ViewModifier {
        let reason: String?
        let onTap: (String) -> Void

        func body(content: Content) -> some View {
            if let reason {
                content
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(reason) }
            } else {
                content
            }
        }
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
