import SwiftUI
import SwiftData

/// Scheduled workouts more than 7 days past their date — too old to still open or
/// reschedule (per spec), so the only action here is bulk-select + cancel.
struct MissedWorkoutsView: View {
    let cutoff: Date

    @Environment(\.modelContext) private var context
    @Query private var allScheduled: [ScheduledWorkout]

    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingCancelConfirm = false

    private var missed: [ScheduledWorkout] {
        allScheduled
            .filter { $0.deletedAt == nil && $0.date < cutoff }
            .sorted { $0.date < $1.date }
    }

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        Group {
            if missed.isEmpty {
                ContentUnavailableView("No Missed Workouts", systemImage: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    if isEditing {
                        headerBar
                        Divider()
                    }
                    List(selection: $selectedIDs) {
                        ForEach(missed) { occurrence in
                            row(occurrence)
                        }
                    }
                    .environment(\.editMode, $editMode)
                    .themedListBackground()
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Missed Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !missed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editMode = isEditing ? .inactive : .active
                        if !isEditing { selectedIDs.removeAll() }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                    }
                }
            }
        }
        .confirmationDialog(
            "Cancel \(selectedIDs.count) scheduled workout\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showingCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel Selected", role: .destructive) { cancelSelected() }
        }
    }

    private var headerBar: some View {
        HStack {
            Button("Select All") {
                selectedIDs = Set(missed.map(\.id))
            }
            .buttonStyle(.borderedProminent)
            Spacer()
            Button("Cancel Selected", role: .destructive) {
                showingCancelConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appDanger)
            .disabled(selectedIDs.isEmpty)
        }
        .padding()
    }

    private func row(_ occurrence: ScheduledWorkout) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "calendar.badge.exclamationmark")
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.workout?.name ?? "Workout")
                Text(occurrence.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func cancelSelected() {
        let toCancel = missed.filter { selectedIDs.contains($0.id) }
        for occurrence in toCancel {
            ScheduledWorkoutService.cancel(occurrence, context: context)
        }
        selectedIDs.removeAll()
    }
}
