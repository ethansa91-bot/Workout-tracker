import SwiftUI
import SwiftData

struct ArchivedWorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.createdAt, order: .reverse) private var allWorkouts: [Workout]

    private var archivedWorkouts: [Workout] {
        allWorkouts.filter { $0.deletedAt == nil && $0.isArchived }
    }

    var body: some View {
        Group {
            if archivedWorkouts.isEmpty {
                ContentUnavailableView(
                    "No Archived Workouts",
                    systemImage: "archivebox",
                    description: Text("Workouts you archive from the Workouts list show up here.")
                )
            } else {
                List {
                    ForEach(archivedWorkouts) { workout in
                        NavigationLink {
                            SessionRecapView(workout: workout)
                        } label: {
                            workoutRow(workout)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                unarchiveWorkout(workout)
                            } label: {
                                Label("Unarchive", systemImage: "archivebox.fill")
                            }
                            .tint(.green)
                        }
                        .contextMenu {
                            Button {
                                unarchiveWorkout(workout)
                            } label: {
                                Label("Unarchive", systemImage: "archivebox.fill")
                            }
                        }
                    }
                }
                .themedListBackground()
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Archives")
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workoutTypeIcon(workout))
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                StatusPill(text: workout.listTypeLabel, tint: .accentColor)
            }
            Spacer()
            if workout.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func workoutTypeIcon(_ workout: Workout) -> String {
        workout.displayType.iconSymbolName
    }

    private func unarchiveWorkout(_ workout: Workout) {
        workout.isArchived = false
        workout.markDirty()
        try? context.save()
    }
}
