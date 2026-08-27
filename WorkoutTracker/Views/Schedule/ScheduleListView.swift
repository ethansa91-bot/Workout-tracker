import SwiftUI
import SwiftData

struct ScheduleListView: View {
    /// Which of the two recap rows is open. Only one at a time — they're summaries, and
    /// two long lists open at once buries the actual schedule below the fold.
    private enum SummaryKind { case missed, completed }

    @Environment(\.modelContext) private var context
    @Query private var allScheduled: [ScheduledWorkout]

    @State private var showingAddSheet = false
    @State private var movingOccurrence: ScheduledWorkout?
    @State private var moveDate = Date()
    @State private var occurrencePendingCancel: ScheduledWorkout?
    @State private var expandedSummary: SummaryKind?
    /// Held here rather than left to the stack, so cloning a locked workout can pop the
    /// original and push the copy in its place.
    @State private var path: [WorkoutRoute] = []

    private var today: Date { ScheduledWorkoutService.startOfDay(.now) }

    private var missedCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: today)!
    }

    private var live: [ScheduledWorkout] {
        allScheduled.filter { $0.deletedAt == nil }
    }

    /// The seven days before today, newest first. Today is deliberately excluded — it's
    /// still in progress, and it has its own section further down.
    private var recentPast: [ScheduledWorkout] {
        live
            .filter { $0.date >= missedCutoff && $0.date < today }
            .sorted { $0.date > $1.date }
    }

    private var missedRecent: [ScheduledWorkout] {
        recentPast.filter { !ScheduledWorkoutService.isCompleted($0) }
    }

    private var completedRecent: [ScheduledWorkout] {
        recentPast.filter { ScheduledWorkoutService.isCompleted($0) }
    }

    /// Today onward. The past is represented entirely by the summary rows above, so
    /// nothing appears in both places. A workout already finished today stays here,
    /// marked Completed, rather than disappearing from the day it belongs to.
    private var upcoming: [ScheduledWorkout] {
        live
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
    }

    /// Older than the seven-day window — too old to still act on, so it keeps its own
    /// bulk-cancel screen rather than folding into the recap rows.
    private var olderMissedCount: Int {
        live.filter { $0.date < missedCutoff }.count
    }

    private var groupedByDay: [(day: Date, items: [ScheduledWorkout])] {
        var groups = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.date) }
        // Today always gets a section, so the page always answers "what am I doing
        // today?" — an empty one reads as a real answer, where a missing one reads as
        // though the page failed to load.
        groups[today] = groups[today] ?? []
        return groups.keys.sorted().map { day in
            (day: day, items: groups[day]!.sorted { ($0.workout?.name ?? "") < ($1.workout?.name ?? "") })
        }
    }

    /// Today's always-present section doesn't count as content — without this the empty
    /// state would never show.
    private var isEmpty: Bool {
        upcoming.isEmpty && missedRecent.isEmpty && completedRecent.isEmpty && olderMissedCount == 0
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                PageTitleBand(title: "Schedule")

                Group {
                    if isEmpty {
                        ContentUnavailableView(
                            "Nothing Scheduled",
                            systemImage: "calendar",
                            description: Text("Tap + to schedule a workout for a date or every week.")
                        )
                    } else {
                        List {
                            if !missedRecent.isEmpty {
                                summarySection(
                                    kind: .missed,
                                    title: "Missed workouts",
                                    systemImage: "exclamationmark.circle.fill",
                                    tint: Color.appDanger,
                                    items: missedRecent
                                )
                            }

                            if !completedRecent.isEmpty {
                                summarySection(
                                    kind: .completed,
                                    title: "Completed workouts",
                                    systemImage: "checkmark.circle.fill",
                                    tint: .green,
                                    items: completedRecent
                                )
                            }

                            if olderMissedCount > 0 {
                                NavigationLink {
                                    MissedWorkoutsView(cutoff: missedCutoff)
                                } label: {
                                    HStack {
                                        Label("Missed Workouts", systemImage: "calendar.badge.exclamationmark")
                                            .foregroundStyle(Color.appDanger)
                                        Spacer()
                                        Text("\(olderMissedCount)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .fullBleedRow()
                            }

                            ForEach(groupedByDay, id: \.day) { group in
                                Section {
                                    if group.items.isEmpty {
                                        // Only ever today — every other key comes from a
                                        // non-empty group.
                                        Text("No workout scheduled for today")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 14)
                                            .fullBleedRow()
                                    } else {
                                        ForEach(group.items) { occurrence in
                                            row(occurrence, isLast: occurrence.id == group.items.last?.id)
                                        }
                                    }
                                } header: {
                                    dayHeader(for: group.day)
                                }
                            }
                        }
                        // `.plain` drops the inset-grouped style's own side margins,
                        // which is the only way the day headers reach both screen edges;
                        // the rows go full-bleed to match, via `fullBleedRow`.
                        .fullBleedList()
                    }
                }
            }
            .background(Color.appBackground)
            .navigationDestination(for: WorkoutRoute.self) { route in
                SessionRecapView(workout: route.workout) { clone in
                    // Replace, not stack: backing out of the copy should reach the
                    // schedule, not the locked workout it was cloned from.
                    path.removeLast()
                    path.append(WorkoutRoute(workout: clone))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
            .alert(
                cancelDialogTitle,
                isPresented: Binding(
                    get: { occurrencePendingCancel != nil },
                    set: { if !$0 { occurrencePendingCancel = nil } }
                )
            ) {
                if let occurrence = occurrencePendingCancel {
                    if occurrence.recurringSchedule != nil {
                        Button("Cancel This Occurrence", role: .destructive) { cancelOccurrence(occurrence) }
                        Button("Cancel Entire Series", role: .destructive) { cancelSeries(occurrence) }
                        Button("Keep", role: .cancel) { }
                    } else {
                        Button("Cancel", role: .destructive) { cancelOccurrence(occurrence) }
                        Button("Keep", role: .cancel) { }
                    }
                }
            }
        }
    }

    // MARK: - Headers

    private func dayHeader(for day: Date) -> some View {
        Text(dayHeaderTitle(for: day))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.appHeaderGray)
            // Zeroed so the band reaches both screen edges; only effective because the
            // list is `.plain` — an inset-grouped section keeps its own side margins no
            // matter what the row insets say.
            .listRowInsets(EdgeInsets())
            // Stock headers uppercase their text, which mangles the date.
            .textCase(nil)
    }

    private static let dayNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter
    }()

    private func dayHeaderTitle(for day: Date) -> String {
        let name = Calendar.current.isDateInToday(day)
            ? "Today"
            : Self.dayNameFormatter.string(from: day)
        return "\(name) · \(Self.dayDateFormatter.string(from: day))"
    }

    // MARK: - Summary rows

    @ViewBuilder
    private func summarySection(
        kind: SummaryKind,
        title: String,
        systemImage: String,
        tint: Color,
        items: [ScheduledWorkout]
    ) -> some View {
        let isExpanded = expandedSummary == kind

        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSummary = isExpanded ? nil : kind
                }
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(items.count)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(Color.appInkMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            // Open, the header is the first of several rows and needs a line under it;
            // closed, it stands alone.
            .fullBleedRow(isLast: !isExpanded)

            if isExpanded {
                ForEach(items) { occurrence in
                    let isLast = occurrence.id == items.last?.id
                    if kind == .missed {
                        summaryRow(occurrence, isLast: isLast)
                            .swipeActions(edge: .leading) { moveButton(occurrence) }
                            .swipeActions(edge: .trailing) { cancelButton(occurrence) }
                    } else {
                        summaryRow(occurrence, isLast: isLast)
                    }
                }
            }
        }
    }

    private func summaryRow(_ occurrence: ScheduledWorkout, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: occurrence.workout.map(workoutTypeIcon) ?? "figure.strengthtraining.traditional")
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.workout?.name ?? "Workout")
                Text(occurrence.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fullBleedRow(isLast: isLast)
    }

    // MARK: - Scheduled rows

    /// Today or later. A finished one stays put with a Completed pill rather than
    /// dropping out of the day it belongs to.
    @ViewBuilder
    private func row(_ occurrence: ScheduledWorkout, isLast: Bool) -> some View {
        Group {
            if let workout = occurrence.workout {
                NavigationLink(value: WorkoutRoute(workout: workout)) {
                    rowContent(occurrence, workout: workout)
                }
            } else {
                rowContent(occurrence, workout: nil)
            }
        }
        .fullBleedRow(isLast: isLast)
        .swipeActions(edge: .leading) { moveButton(occurrence) }
        .swipeActions(edge: .trailing) { cancelButton(occurrence) }
        .contextMenu {
            moveButton(occurrence)
            cancelButton(occurrence)
        }
    }

    private func rowContent(_ occurrence: ScheduledWorkout, workout: Workout?) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workout.map(workoutTypeIcon) ?? "figure.strengthtraining.traditional")
            VStack(alignment: .leading, spacing: 3) {
                Text(workout?.name ?? "Workout")
                if ScheduledWorkoutService.isCompleted(occurrence) {
                    StatusPill(text: "Completed", tint: .green)
                } else if occurrence.recurringSchedule != nil {
                    StatusPill(text: "Weekly", tint: .accentColor)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func moveButton(_ occurrence: ScheduledWorkout) -> some View {
        Button {
            movingOccurrence = occurrence
            moveDate = occurrence.date
        } label: {
            Label("Move", systemImage: "calendar")
        }
        .tint(.blue)
    }

    private func cancelButton(_ occurrence: ScheduledWorkout) -> some View {
        Button(role: .destructive) {
            occurrencePendingCancel = occurrence
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
    }

    private func workoutTypeIcon(_ workout: Workout) -> String {
        workout.displayType.iconSymbolName
    }

    // MARK: - Move / cancel

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
}
