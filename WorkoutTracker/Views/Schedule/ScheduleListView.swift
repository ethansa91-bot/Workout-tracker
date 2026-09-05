import SwiftUI
import SwiftData

struct ScheduleListView: View {
    /// Which of the two recap rows is open. Only one at a time — they're summaries, and
    /// two long lists open at once buries the actual schedule below the fold.
    private enum SummaryKind { case missed, completed }

    /// A workout finished inside the recap window, flattened to what a row needs.
    ///
    /// Session-driven rather than occurrence-driven: a workout done spontaneously is
    /// just as done as a scheduled one, and only the session records that it happened
    /// at all. Flattening here is what lets the completed and missed groups — which
    /// have different sources — share one row view.
    private struct CompletedWorkout: Identifiable {
        /// The session's, so two runs of the same workout on one day stay distinct.
        let id: UUID
        let name: String
        let date: Date
        let icon: String
        /// What the row opens. `nil` where the workout behind the session is gone —
        /// `name` and `icon` keep their own fallbacks, so the row still renders, just
        /// without anywhere to go.
        let workout: Workout?
    }

    @Environment(\.modelContext) private var context
    @Query private var allScheduled: [ScheduledWorkout]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

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

    /// Everything actually finished in the window, scheduled or not — so a spontaneous
    /// workout still counts toward the seven-day tally. Taken from sessions rather than
    /// from `recentPast`, which by construction only knows about planned days.
    ///
    /// A scheduled workout that was done appears here and not in `missedRecent`, so it
    /// still shows exactly once.
    private var completedRecent: [CompletedWorkout] {
        allSessions
            .filter { session in
                session.deletedAt == nil
                    && session.status == .finished
                    // `missedCutoff` is a start-of-day, so a session anywhere in that
                    // day qualifies. Today is excluded for the same reason as above.
                    && session.startedAt >= missedCutoff
                    && session.startedAt < today
            }
            // The query is already newest-first, matching `recentPast`'s order.
            .map { session in
                CompletedWorkout(
                    id: session.id,
                    name: session.workout?.name ?? "Workout",
                    date: session.startedAt,
                    icon: session.workout.map(workoutTypeIcon) ?? "figure.strengthtraining.traditional",
                    workout: session.workout
                )
            }
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
                            // First, and one quiet line: it's a doorway to a screenful of
                            // stale occurrences, not part of the recap, so it says how
                            // many there are and gets out of the way of the days below.
                            if olderMissedCount > 0 {
                                olderMissedLine
                            }

                            // Both recaps live under one band, so the window they cover
                            // is named once instead of being left implicit.
                            if !missedRecent.isEmpty || !completedRecent.isEmpty {
                                Section {
                                    missedGroup
                                    completedGroup
                                } header: {
                                    bandHeader("Last 7 days")
                                }
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
                        // The green title band sits directly above, and a plain list's
                        // own top inset left a strip of ground between it and the first
                        // gray band. Local to this screen: elsewhere a list opens with a
                        // `FormSectionHeader`, which wants its top padding.
                        .contentMargins(.top, 0, for: .scrollContent)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .workout(let workout):
                    SessionRecapView(workout: workout) { clone in
                        // Replace, not stack: backing out of the copy should reach the
                        // schedule, not the locked workout it was cloned from.
                        path.removeLast()
                        path.append(.workout(clone))
                    }
                // Nothing here pushes Archives, but the route type is shared with the
                // Workouts stack and the destination has to be total.
                case .archives:
                    ArchivedWorkoutsView()
                case .olderMissed(let cutoff):
                    MissedWorkoutsView(cutoff: cutoff)
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

    /// The whole "Older than 7 days" section, reduced to one quiet line.
    ///
    /// Deliberately not a `ListBandHeader` like the sections below it: a band announces
    /// something you're meant to read, and stale occurrences are the opposite — a number
    /// worth knowing and a way in, ranked *below* every band on the page despite sitting
    /// above them. Muted caption on the page's own ground, indented to the same 20pt as
    /// a band title so it still lines up with "Last 7 days".
    private var olderMissedLine: some View {
        Button {
            path.append(.olderMissed(cutoff: missedCutoff))
        } label: {
            HStack(spacing: 4) {
                Text("Older than 7 days (\(olderMissedCount))")
                // The one thing that isn't plain text: without it nothing says the line
                // opens anything, and it's the only way to reach the bulk cancel.
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(Color.appInkMuted)
            .padding(.horizontal, HeaderMetrics.bandHorizontalInset)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func bandHeader(_ title: String) -> some View {
        ListBandHeader(title: title)
    }

    private func dayHeader(for day: Date) -> some View {
        bandHeader(dayHeaderTitle(for: day))
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

    // Both groups sit in one section now, so `isLast` — which hides the separator to
    // close a group off — can only be true on the section's actual final row. The
    // completed group renders second, so whenever it has items the missed group never
    // closes the section.

    @ViewBuilder
    private var missedGroup: some View {
        if !missedRecent.isEmpty {
            let isExpanded = expandedSummary == .missed
            let closesSection = completedRecent.isEmpty

            summaryToggleRow(
                kind: .missed,
                title: "Missed workouts",
                systemImage: "exclamationmark.circle.fill",
                tint: Color.appDanger,
                count: missedRecent.count,
                isLast: !isExpanded && closesSection
            )

            if isExpanded {
                ForEach(missedRecent) { occurrence in
                    summaryRow(
                        name: occurrence.workout?.name ?? "Workout",
                        date: occurrence.date,
                        icon: occurrence.workout.map(workoutTypeIcon) ?? "figure.strengthtraining.traditional",
                        workout: occurrence.workout,
                        isLast: occurrence.id == missedRecent.last?.id && closesSection
                    )
                    .swipeActions(edge: .leading) { moveButton(occurrence) }
                    .swipeActions(edge: .trailing) { cancelButton(occurrence, isSwipe: true) }
                }
            }
        }
    }

    @ViewBuilder
    private var completedGroup: some View {
        if !completedRecent.isEmpty {
            let isExpanded = expandedSummary == .completed

            summaryToggleRow(
                kind: .completed,
                title: "Completed workouts",
                systemImage: "checkmark.circle.fill",
                tint: .green,
                count: completedRecent.count,
                isLast: !isExpanded
            )

            if isExpanded {
                ForEach(completedRecent) { completed in
                    summaryRow(
                        name: completed.name,
                        date: completed.date,
                        icon: completed.icon,
                        workout: completed.workout,
                        isLast: completed.id == completedRecent.last?.id
                    )
                }
            }
        }
    }

    private func summaryToggleRow(
        kind: SummaryKind,
        title: String,
        systemImage: String,
        tint: Color,
        count: Int,
        isLast: Bool
    ) -> some View {
        let isExpanded = expandedSummary == kind

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedSummary = isExpanded ? nil : kind
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(tint)
                Spacer()
                Text("\(count)")
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
        // closed, it stands alone — unless another group follows it in the section.
        .fullBleedRow(isLast: isLast)
    }

    /// Takes values rather than a model, so a missed occurrence and a completed session
    /// render as the same row despite coming from different types.
    ///
    /// Both open the workout, which is why `workout` comes in alongside the name it was
    /// already flattened to — the completed side reaches it through the session. Where
    /// the workout is gone the row still renders, just without a link.
    @ViewBuilder
    private func summaryRow(name: String, date: Date, icon: String, workout: Workout?, isLast: Bool) -> some View {
        Group {
            if let workout {
                NavigationLink(value: WorkoutRoute.workout(workout)) {
                    summaryRowContent(name: name, date: date, icon: icon)
                }
            } else {
                summaryRowContent(name: name, date: date, icon: icon)
            }
        }
        .fullBleedRow(isLast: isLast)
    }

    private func summaryRowContent(name: String, date: Date, icon: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                // Named day first, like the day bands below: "Sep 2" alone doesn't say
                // which day of the week it was, which is what a past week is read by.
                Text("\(Self.dayNameFormatter.string(from: date)) · \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Scheduled rows

    /// Today or later. A finished one stays put with a Completed pill rather than
    /// dropping out of the day it belongs to.
    @ViewBuilder
    private func row(_ occurrence: ScheduledWorkout, isLast: Bool) -> some View {
        Group {
            if let workout = occurrence.workout {
                NavigationLink(value: WorkoutRoute.workout(workout)) {
                    rowContent(occurrence, workout: workout)
                }
            } else {
                rowContent(occurrence, workout: nil)
            }
        }
        .fullBleedRow(isLast: isLast)
        .swipeActions(edge: .leading) { moveButton(occurrence) }
        .swipeActions(edge: .trailing) { cancelButton(occurrence, isSwipe: true) }
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

    /// `isSwipe` drops the destructive role, which a swipe action interprets as "remove
    /// this row now" and animates away before the confirmation has even been answered —
    /// the row then reappeared behind the alert. A context menu has no such behavior, so
    /// that copy keeps the role and its red styling.
    private func cancelButton(_ occurrence: ScheduledWorkout, isSwipe: Bool = false) -> some View {
        Button(role: isSwipe ? nil : .destructive) {
            occurrencePendingCancel = occurrence
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
        .tint(Color.appDanger)
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
