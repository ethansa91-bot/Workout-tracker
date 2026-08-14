import SwiftUI
import SwiftData

/// Single-workout picker for the schedule-creation flow — every non-archived
/// workout, locked or not (scheduling doesn't touch `isLocked`, which only tracks
/// session history).
struct WorkoutPickerView: View {
    let onSelect: (Workout) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workout.name) private var allWorkouts: [Workout]

    @State private var searchText = ""

    private var filtered: [Workout] {
        allWorkouts.filter { workout in
            workout.deletedAt == nil
                && !workout.isArchived
                && (searchText.isEmpty || workout.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { workout in
                Button {
                    onSelect(workout)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: workoutTypeIcon(workout))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.name)
                            StatusPill(text: workout.listTypeLabel, tint: .accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 2)
                }
            }
            .themedListBackground()
            .searchable(text: $searchText, prompt: "Search workouts")
            .navigationTitle("Choose Workout")
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

    private func workoutTypeIcon(_ workout: Workout) -> String {
        switch workout.displayType {
        case .time: return "timer"
        case .rep: return "list.number"
        case .mixed: return "square.stack.3d.up.fill"
        case .empty: return "list.bullet.rectangle"
        }
    }
}
