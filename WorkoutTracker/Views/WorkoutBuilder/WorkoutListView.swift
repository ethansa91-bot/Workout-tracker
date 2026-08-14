import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.createdAt, order: .reverse) private var allWorkouts: [Workout]

    @State private var showingNewWorkoutSheet = false
    @State private var newWorkoutDestination: WorkoutEditDestination?

    private var workouts: [Workout] {
        allWorkouts.filter { $0.deletedAt == nil && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
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
                                NavigationLink {
                                    SessionRecapView(workout: workout)
                                } label: {
                                    workoutRow(workout)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        cloneWorkout(workout)
                                    } label: {
                                        Label("Clone", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
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
                                        archiveWorkout(workout)
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                }
                            }
                        } footer: {
                            Text("A lock means that workout has already been used and can't be edited or deleted. Swipe right on a workout to clone it, or left to archive it.")
                        }
                    }
                    .themedListBackground()
                }
            }
            .background(Color.appBackground)
            .navigationTitle("My Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ArchivedWorkoutsView()
                    } label: {
                        Label("Archives", systemImage: "archivebox")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewWorkoutSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewWorkoutSheet) {
                NewWorkoutSheet(onCreate: createWorkout)
            }
            .navigationDestination(item: $newWorkoutDestination) { destination in
                switch destination {
                case .workout(let workout):
                    SessionRecapView(workout: workout)
                case .block(let block):
                    BlockEditorView(block: block, onSaveNavigatesToRecap: true)
                }
            }
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workoutTypeIcon(workout))
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                StatusPill(text: workout.listTypeLabel, tint: .accentColor)
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
        .padding(.vertical, 2)
    }

    private func workoutTypeIcon(_ workout: Workout) -> String {
        switch workout.displayType {
        case .time: return "timer"
        case .rep: return "list.number"
        case .mixed: return "square.stack.3d.up.fill"
        case .empty: return "list.bullet.rectangle"
        }
    }

    private func cloneWorkout(_ workout: Workout) {
        _ = WorkoutCloningService.clone(workout, context: context)
    }

    private func archiveWorkout(_ workout: Workout) {
        workout.isArchived = true
        workout.markDirty()
        try? context.save()
    }

    private func createWorkout(name: String, kind: WorkoutKind) {
        let workout = WorkoutEditingService.createWorkout(name: name, kind: kind, context: context)
        guard kind != .personalized else {
            newWorkoutDestination = .workout(workout)
            return
        }
        do {
            let block = try WorkoutEditingService.addBlock(to: workout, type: kind == .byTime ? .time : .rep, context: context)
            newWorkoutDestination = .block(block)
        } catch {
            newWorkoutDestination = .workout(workout)
        }
    }
}
