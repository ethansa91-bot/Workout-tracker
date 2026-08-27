import SwiftUI
import SwiftData

struct ArchivedWorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.createdAt, order: .reverse) private var allWorkouts: [Workout]

    @State private var pendingDelete: Workout?

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
                        NavigationLink(value: WorkoutRoute(workout: workout)) {
                            workoutRow(workout)
                        }
                        .fullBleedRow(isLast: workout.id == archivedWorkouts.last?.id)
                        .swipeActions(edge: .leading) {
                            Button {
                                unarchiveWorkout(workout)
                            } label: {
                                Label("Unarchive", systemImage: "archivebox.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            // Same rule as the Workouts list: history behind a workout
                            // means archive-only.
                            if !workout.isLocked {
                                Button(role: .destructive) {
                                    pendingDelete = workout
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                unarchiveWorkout(workout)
                            } label: {
                                Label("Unarchive", systemImage: "archivebox.fill")
                            }
                            if !workout.isLocked {
                                Button(role: .destructive) {
                                    pendingDelete = workout
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .fullBleedList()
                .alert("Delete \"\(pendingDelete?.name ?? "")\"?", isPresented: deleteAlertBinding) {
                    Button("Delete", role: .destructive) { deleteWorkout() }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                } message: {
                    Text("This workout and all its sections will be permanently deleted.")
                }
            }
        }
        .background(Color.appBackground)
        .safeAreaInset(edge: .top, spacing: 0) { PushedTitleBand(title: "Archives") }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func workoutTypeIcon(_ workout: Workout) -> String {
        workout.displayType.iconSymbolName
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    /// Hard delete — `sectionsStorage` cascades. The `isLocked` re-check guards the gap
    /// between the swipe and the confirmation.
    private func deleteWorkout() {
        guard let workout = pendingDelete, !workout.isLocked else {
            pendingDelete = nil
            return
        }
        context.delete(workout)
        try? context.save()
        pendingDelete = nil
    }

    private func unarchiveWorkout(_ workout: Workout) {
        workout.isArchived = false
        workout.markDirty()
        try? context.save()
    }
}
