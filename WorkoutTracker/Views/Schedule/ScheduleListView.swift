import SwiftUI
import SwiftData

struct ScheduleListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allScheduled: [ScheduledWorkout]

    @State private var showingAddSheet = false
    @State private var movingOccurrence: ScheduledWorkout?
    @State private var moveDate = Date()
    @State private var occurrencePendingCancel: ScheduledWorkout?

    private var missedCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: ScheduledWorkoutService.startOfDay(.now))!
    }

    private var visibleScheduled: [ScheduledWorkout] {
        allScheduled
            .filter { $0.deletedAt == nil && $0.date >= missedCutoff }
            .sorted { $0.date < $1.date }
    }

    private var missedCount: Int {
        allScheduled.filter { $0.deletedAt == nil && $0.date < missedCutoff }.count
    }

    private var groupedByDay: [(day: Date, items: [ScheduledWorkout])] {
        let groups = Dictionary(grouping: visibleScheduled) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted().map { day in
            (day: day, items: groups[day]!.sorted { ($0.workout?.name ?? "") < ($1.workout?.name ?? "") })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleScheduled.isEmpty && missedCount == 0 {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar",
                        description: Text("Tap + to schedule a workout for a date or every week.")
                    )
                } else {
                    List {
                        if missedCount > 0 {
                            NavigationLink {
                                MissedWorkoutsView(cutoff: missedCutoff)
                            } label: {
                                HStack {
                                    Label("Missed Workouts", systemImage: "exclamationmark.circle.fill")
                                        .foregroundStyle(Color.appDanger)
                                    Spacer()
                                    Text("\(missedCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ForEach(groupedByDay, id: \.day) { group in
                            Section(header: Text(sectionTitle(for: group.day))) {
                                ForEach(group.items) { occurrence in
                                    row(occurrence)
                                }
                            }
                        }
                    }
                    .themedListBackground()
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddScheduledWorkoutView()
            }
            .sheet(item: $movingOccurrence) { occurrence in
                moveSheet(for: occurrence)
            }
            .confirmationDialog(
                cancelDialogTitle,
                isPresented: Binding(
                    get: { occurrencePendingCancel != nil },
                    set: { if !$0 { occurrencePendingCancel = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let occurrence = occurrencePendingCancel {
                    if occurrence.recurringSchedule != nil {
                        Button("Cancel This Occurrence", role: .destructive) { cancelOccurrence(occurrence) }
                        Button("Cancel Entire Series", role: .destructive) { cancelSeries(occurrence) }
                    } else {
                        Button("Cancel", role: .destructive) { cancelOccurrence(occurrence) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ occurrence: ScheduledWorkout) -> some View {
        let missed = occurrence.date < ScheduledWorkoutService.startOfDay(.now)
        Group {
            if let workout = occurrence.workout {
                NavigationLink {
                    SessionRecapView(workout: workout)
                } label: {
                    rowContent(occurrence, workout: workout, missed: missed)
                }
            } else {
                rowContent(occurrence, workout: nil, missed: missed)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                movingOccurrence = occurrence
                moveDate = occurrence.date
            } label: {
                Label("Move", systemImage: "calendar")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                occurrencePendingCancel = occurrence
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
        }
        .contextMenu {
            Button {
                movingOccurrence = occurrence
                moveDate = occurrence.date
            } label: {
                Label("Move", systemImage: "calendar")
            }
            Button(role: .destructive) {
                occurrencePendingCancel = occurrence
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
        }
    }

    private func rowContent(_ occurrence: ScheduledWorkout, workout: Workout?, missed: Bool) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workout.map(workoutTypeIcon) ?? "figure.strengthtraining.traditional")
            VStack(alignment: .leading, spacing: 3) {
                Text(workout?.name ?? "Workout")
                if missed {
                    StatusPill(text: "Missed", tint: Color.appDanger)
                } else if occurrence.recurringSchedule != nil {
                    StatusPill(text: "Weekly", tint: .accentColor)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func workoutTypeIcon(_ workout: Workout) -> String {
        workout.displayType.iconSymbolName
    }

    private func moveSheet(for occurrence: ScheduledWorkout) -> some View {
        NavigationStack {
            Form {
                DatePicker("New date", selection: $moveDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Move Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { movingOccurrence = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ScheduledWorkoutService.move(occurrence, to: moveDate, context: context)
                        movingOccurrence = nil
                    }
                }
            }
        }
    }

    private var cancelDialogTitle: String {
        guard let occurrence = occurrencePendingCancel, let workout = occurrence.workout else { return "Cancel this workout?" }
        return "Cancel \"\(workout.name)\"?"
    }

    private func cancelOccurrence(_ occurrence: ScheduledWorkout) {
        ScheduledWorkoutService.cancel(occurrence, context: context)
        occurrencePendingCancel = nil
    }

    private func cancelSeries(_ occurrence: ScheduledWorkout) {
        guard let schedule = occurrence.recurringSchedule else { return }
        ScheduledWorkoutService.cancelSeries(schedule, context: context)
        occurrencePendingCancel = nil
    }

    private func sectionTitle(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day)
    }
}
