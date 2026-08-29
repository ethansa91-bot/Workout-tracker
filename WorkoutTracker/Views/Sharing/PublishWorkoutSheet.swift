import SwiftUI
import SwiftData

/// Choose which of your workouts other people can see.
///
/// Publishing is per-workout and reversible: the list shows current state rather than
/// making the user remember what they've already shared.
struct PublishWorkoutSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Workout.name) private var allWorkouts: [Workout]

    @State private var publishedIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var busyID: UUID?
    @State private var errorMessage: String?

    private var workouts: [Workout] {
        allWorkouts.filter { $0.deletedAt == nil && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "square.and.arrow.up",
                        description: Text("Create a workout first.")
                    )
                } else {
                    List(workouts) { workout in
                        Button {
                            Task { await toggle(workout) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: publishedIDs.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(publishedIDs.contains(workout.id) ? Color.appAccent : Color.appInkMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.name).foregroundStyle(Color.appInk)
                                    Text(subtitle(for: workout))
                                        .font(.caption)
                                        .foregroundStyle(Color.appInkMuted)
                                }
                                Spacer()
                                if busyID == workout.id { ProgressView() }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(busyID != nil)
                    }
                    .themedListBackground()
                }
            }
            .navigationTitle("Publish Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadPublished() }
            .alert("Publishing", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func subtitle(for workout: Workout) -> String {
        let count = workout.sortedSections.count
        let state = publishedIDs.contains(workout.id) ? "Published" : "Not published"
        return "\(count) Section\(count == 1 ? "" : "s") · \(state)"
    }

    private func loadPublished() async {
        isLoading = true
        defer { isLoading = false }
        do {
            publishedIDs = try await SharingService.myPublishedWorkoutIDs()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }

    private func toggle(_ workout: Workout) async {
        busyID = workout.id
        defer { busyID = nil }
        do {
            if publishedIDs.contains(workout.id) {
                try await SharingService.unpublish(workoutID: workout.id)
                publishedIDs.remove(workout.id)
            } else {
                // Built on the main actor from live model objects, then handed to the
                // network call as a value — the bundle must not hold model references.
                let bundle = SharedWorkoutBuilder.makeBundle(for: workout)
                try await SharingService.publish(bundle)
                publishedIDs.insert(workout.id)
            }
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }
}
