import SwiftUI
import SwiftData

/// Sheet for scheduling a workout: choose the workout, then either a single
/// date or a weekly pattern (multiple days of the week at once).
///
/// Opened two ways. From the Schedule tab's `+` the workout is unknown and the first row
/// picks one. Opened from a workout — its own screen, or a swipe on the Workouts list —
/// `preselectedWorkout` is set, that row is dropped, and the sheet presents as a
/// translucent panel over the page rather than as a full opaque screen.
struct AddScheduledWorkoutView: View {
    /// Non-nil when opened from a workout that's already known — the picker row is
    /// dropped and the workout can't be changed.
    let preselectedWorkout: Workout?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWorkout: Workout?
    @State private var showingWorkoutPicker = false
    @State private var mode: ScheduleMode = .oneDate
    @State private var date = Date()
    @State private var selectedWeekdays: Set<Int> = []
    @State private var endMode: EndMode = .afterWeeks
    @State private var weekCount = 8
    @State private var customEndDate = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: .now) ?? .now

    init(preselectedWorkout: Workout? = nil) {
        self.preselectedWorkout = preselectedWorkout
        _selectedWorkout = State(initialValue: preselectedWorkout)
    }

    private enum ScheduleMode: String, CaseIterable {
        case oneDate = "One Date"
        case weekly = "Weekly"
    }

    private enum EndMode: String, CaseIterable {
        case afterWeeks = "After N Weeks"
        case onDate = "On Date"
    }

    private var canSave: Bool {
        guard selectedWorkout != nil else { return false }
        return mode == .oneDate || !selectedWeekdays.isEmpty
    }

    private var resolvedEndDate: Date {
        switch endMode {
        case .afterWeeks:
            return Calendar.current.date(byAdding: .weekOfYear, value: weekCount, to: .now) ?? .now
        case .onDate:
            return customEndDate
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if preselectedWorkout == nil {
                    Section("Workout") {
                        Button {
                            showingWorkoutPicker = true
                        } label: {
                            HStack {
                                Text(selectedWorkout?.name ?? "Choose Workout")
                                    .foregroundStyle(selectedWorkout == nil ? Color.secondary : Color.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker("Schedule type", selection: $mode) {
                        ForEach(ScheduleMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .oneDate:
                    Section("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                case .weekly:
                    Section("Repeats On") {
                        ForEach(1...7, id: \.self) { weekday in
                            weekdayRow(weekday)
                        }
                    }

                    Section("Ends") {
                        Picker("Ends", selection: $endMode) {
                            ForEach(EndMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch endMode {
                        case .afterWeeks:
                            Stepper("\(weekCount) week\(weekCount == 1 ? "" : "s")", value: $weekCount, in: 1...52)
                        case .onDate:
                            DatePicker("End date", selection: $customEndDate, in: Date.now..., displayedComponents: .date)
                        }
                    }
                }
            }
            // Opaque cream when this is the whole screen; transparent when it's the
            // translucent panel, so the material behind it shows through instead of
            // being painted over.
            .modifier(FormBackground(isGlass: preselectedWorkout != nil))
            // The name is the only thing identifying which workout is being scheduled
            // once the picker row is gone.
            .navigationTitle(preselectedWorkout?.name ?? "Schedule Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(preselectedWorkout == nil ? "Save" : "Schedule") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingWorkoutPicker) {
                WorkoutPickerView { workout in
                    selectedWorkout = workout
                }
            }
        }
        .modifier(GlassPresentation(isGlass: preselectedWorkout != nil))
    }

    private func weekdayRow(_ weekday: Int) -> some View {
        let symbols = Calendar.current.weekdaySymbols
        let isSelected = selectedWeekdays.contains(weekday)
        return Button {
            toggle(weekday)
        } label: {
            HStack {
                Text(symbols[weekday - 1])
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func toggle(_ weekday: Int) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func save() {
        guard let selectedWorkout else { return }
        switch mode {
        case .oneDate:
            ScheduledWorkoutService.createOneOff(workout: selectedWorkout, date: date, context: context)
        case .weekly:
            ScheduledWorkoutService.createWeekly(workout: selectedWorkout, weekdays: Array(selectedWeekdays), endDate: resolvedEndDate, context: context)
        }
        dismiss()
    }
}

/// Applied conditionally rather than with an `if` in the view body: swapping which
/// modifier a view has is a structural change SwiftUI would rebuild the form for.
private struct FormBackground: ViewModifier {
    let isGlass: Bool

    func body(content: Content) -> some View {
        if isGlass {
            content.scrollContentBackground(.hidden)
        } else {
            content.themedListBackground()
        }
    }
}

/// A detent sheet rather than the app's fixed-size `.presentationCompactAdaptation`
/// popovers: the weekly options — mode picker, seven weekday rows, end mode, stepper or
/// date — don't fit a 320x400 popover. The material still reads as a panel over the page.
private struct GlassPresentation: ViewModifier {
    let isGlass: Bool

    /// Opens tall and can be dragged down. A detent set alone opens at its smallest,
    /// which cut the calendar off halfway through the month.
    @State private var detent: PresentationDetent = .large

    func body(content: Content) -> some View {
        if isGlass {
            content
                .presentationDetents([.medium, .large], selection: $detent)
                .presentationBackground(.ultraThinMaterial)
        } else {
            content
        }
    }
}
