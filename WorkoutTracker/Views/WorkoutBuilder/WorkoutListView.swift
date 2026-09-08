import SwiftUI
import SwiftData

/// One route type for the whole stack, not one per screen.
///
/// `ArchivedWorkoutsView` is pushed into `WorkoutListView`'s stack and shares its typed
/// path — and a typed path only carries its own element type, so a separate route struct
/// for Archives could never enter it and its links would silently do nothing. A single
/// type keeps both screens pushing onto the one path, and a single
/// `navigationDestination` on the stack root handles them.
///
/// Archives is a case here rather than a plain `NavigationLink { ArchivedWorkoutsView() }`
/// for the same reason: **every push in a path-driven stack has to go through the path.**
/// A destination-based link doesn't, so the path stayed empty while Archives was on
/// screen; the workout Archives then pushed took path slot 0 — the slot Archives was
/// already occupying out of band — and SwiftUI built the workout *underneath* it. The tap
/// looked dead and Back revealed the workout.
enum WorkoutRoute: Hashable {
    case workout(Workout)
    case archives
    /// The Schedule's bulk-cancel screen for occurrences older than the recap window.
    /// A case for the same reason Archives is one, and it was previously a
    /// destination-based link — the out-of-band push this comment describes.
    case olderMissed(cutoff: Date)
}

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.createdAt, order: .reverse) private var allWorkouts: [Workout]

    @State private var showingNewWorkoutAlert = false
    @State private var newWorkoutName = ""
    @State private var pendingDelete: Workout?
    /// The workout the schedule sheet is open for, if any.
    @State private var schedulingWorkout: Workout?
    /// Held here rather than left to the stack, so cloning a locked workout can pop the
    /// original and push the copy in its place.
    @State private var path: [WorkoutRoute] = []

    @State private var tagFilter = WorkoutTagFilter()

    private var workouts: [Workout] {
        allWorkouts.filter {
            $0.deletedAt == nil && !$0.isArchived && !$0.isSupersededVersion && tagFilter.matches($0.sortedTags)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                PageTitleBand(title: "Workouts")
                WorkoutTagFilterBar(filter: $tagFilter)
                workoutsContent
            }
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: WorkoutRoute.archives) {
                        Label("Archives", systemImage: "archivebox")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newWorkoutName = ""
                        showingNewWorkoutAlert = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .alert("New Workout", isPresented: $showingNewWorkoutAlert) {
                TextField("Workout name", text: $newWorkoutName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let trimmed = newWorkoutName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    createWorkout(name: trimmed)
                }
            }
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .workout(let workout):
                    SessionRecapView(workout: workout) { clone in
                        // Reset, not stack: backing out of the copy should reach this
                        // list, not the locked workout the user was just told they
                        // can't edit — nor, if this came from several pushes deep (a
                        // past version opened from version history), any of the
                        // screens in between. A full reset lands on the list however
                        // deep the original workout was reached from.
                        path = [.workout(clone)]
                    }
                case .archives:
                    ArchivedWorkoutsView()
                // Only the Schedule pushes this, but the route type is shared with that
                // stack and the destination has to be total.
                case .olderMissed(let cutoff):
                    MissedWorkoutsView(cutoff: cutoff)
                }
            }
        }
    }

    @ViewBuilder
    private var workoutsContent: some View {
        // Read once, not once per row — `workouts.last?.id` inside the `ForEach` re-ran
        // the filter for every row.
        let workouts = self.workouts
        let lastID = workouts.last?.id

        if workouts.isEmpty {
            ContentUnavailableView(
                "No Workouts Yet",
                systemImage: "list.bullet.rectangle",
                description: Text("Tap + to build a time, repetition, or mixed workout.")
            )
        } else {
            List {
                Section {
                    ForEach(workouts) { workout in
                        NavigationLink(value: WorkoutRoute.workout(workout)) {
                            workoutRow(workout)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                cloneWorkout(workout)
                            } label: {
                                Label("Clone", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                            Button {
                                schedulingWorkout = workout
                            } label: {
                                Label("Schedule", systemImage: "calendar.badge.plus")
                            }
                            .tint(Color.appAccent)
                        }
                        .swipeActions(edge: .trailing) {
                            // Deleting a workout with history behind it would strand
                            // that history, so it's archive-only once locked.
                            if !workout.isLocked {
                            // Not `role: .destructive`: a destructive swipe button
                            // plays the row-removal animation the moment it's tapped,
                            // before any data changes — so the row vanished, the
                            // confirmation appeared, and the row came back. Tinted
                            // instead; the role belongs on the alert's confirm button.
                                Button {
                                    pendingDelete = workout
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color.appDanger)
                            }
                            Button {
                                archiveWorkout(workout)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                cloneWorkout(workout)
                            } label: {
                                Label("Clone", systemImage: "doc.on.doc")
                            }
                            Button {
                                schedulingWorkout = workout
                            } label: {
                                Label("Schedule", systemImage: "calendar.badge.plus")
                            }
                            Button {
                                archiveWorkout(workout)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            if !workout.isLocked {
                                Button(role: .destructive) {
                                    pendingDelete = workout
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .fullBleedRow(isLast: workout.id == lastID)
                    }
                } footer: {
                    Text("A lock means that workout has already been used, so its sections can't be changed and it can't be deleted. Swipe right on a workout to clone or schedule it, or left to archive or delete it.")
                        .font(.footnote)
                        .foregroundStyle(Color.appInkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .fullBleedList()
            .sheet(item: $schedulingWorkout) { workout in
                AddScheduledWorkoutView(preselectedWorkout: workout)
            }
            .alert("Delete \"\(pendingDelete?.name ?? "")\"?", isPresented: deleteAlertBinding) {
                Button("Delete", role: .destructive) { deleteWorkout() }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This workout and all its sections will be permanently deleted.")
            }
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workoutTypeIcon(workout))
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                StatusPill(text: workout.listTypeLabel, tint: .accentColor)
                RowTagPills(tags: workout.sortedTags)
                if let notes = workout.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

    private func cloneWorkout(_ workout: Workout) {
        _ = WorkoutCloningService.clone(workout, context: context)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    /// Hard delete — `sectionsStorage` cascades, so the sections and their steps go
    /// with it. The `isLocked` re-check guards the gap between the swipe and the
    /// confirmation, in which a session could have started.
    private func deleteWorkout() {
        guard let workout = pendingDelete, !workout.isLocked else {
            pendingDelete = nil
            return
        }
        context.delete(workout)
        try? context.save()
        pendingDelete = nil
    }

    private func archiveWorkout(_ workout: Workout) {
        workout.isArchived = true
        workout.markDirty()
        try? context.save()
    }

    private func createWorkout(name: String) {
        let workout = WorkoutEditingService.createWorkout(name: name, context: context)
        // Onto the same path the list pushes with, so a workout opens the same way
        // however it was reached — and a clone can replace it later.
        path.append(.workout(workout))
    }
}
