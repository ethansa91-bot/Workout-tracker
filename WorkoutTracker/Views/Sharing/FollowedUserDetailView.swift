import SwiftUI
import SwiftData

/// Someone's published workouts, with the option to save one into your own library.
struct FollowedUserDetailView: View {
    let user: FollowedUser

    @Environment(\.modelContext) private var context

    @State private var summaries: [SharedWorkoutSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    /// Decoded and checked against the local catalog before the user is asked to
    /// confirm — nothing is written until they do.
    @State private var pendingPlan: SharedWorkoutPlan?
    @State private var downloadingID: String?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else if summaries.isEmpty {
                ContentUnavailableView(
                    "Nothing Published",
                    systemImage: "tray",
                    description: Text("\(user.resolvedDisplayName) hasn't published any workouts yet.")
                )
            } else {
                ForEach(summaries) { summary in
                    Button {
                        Task { await prepareDownload(summary) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.name).foregroundStyle(Color.appInk)
                                Text(subtitle(for: summary))
                                    .font(.caption)
                                    .foregroundStyle(Color.appInkMuted)
                            }
                            Spacer()
                            if downloadingID == summary.id {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadingID != nil)
                }
            }
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) { PushedTitleBand(title: user.resolvedDisplayName) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Save this workout?", isPresented: Binding(
            get: { pendingPlan != nil },
            set: { if !$0 { pendingPlan = nil } }
        )) {
            Button("Save") { performImport() }
            Button("Cancel", role: .cancel) { pendingPlan = nil }
        } message: {
            Text(confirmationMessage)
        }
        .alert("Saved", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK") { infoMessage = nil }
        } message: {
            Text(infoMessage ?? "")
        }
        .alert("Couldn't Load", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func subtitle(for summary: SharedWorkoutSummary) -> String {
        let sections = "\(summary.sectionCount) Section\(summary.sectionCount == 1 ? "" : "s")"
        return summary.summary.isEmpty ? sections : "\(sections) · \(summary.summary)"
    }

    /// Names exactly what will be added, because a download can create catalog rows and
    /// that shouldn't happen silently.
    private var confirmationMessage: String {
        guard let plan = pendingPlan else { return "" }
        var lines = ["“\(plan.workoutName)” will be saved to your workouts."]
        if !plan.newExerciseNames.isEmpty {
            let names = plan.newExerciseNames.prefix(6).joined(separator: ", ")
            let extra = plan.newExerciseNames.count - min(6, plan.newExerciseNames.count)
            lines.append(
                "These exercises aren't in your library and will be added: \(names)"
                    + (extra > 0 ? ", and \(extra) more." : ".")
            )
        }
        lines.append("Your existing workouts and exercises aren't changed.")
        return lines.joined(separator: "\n\n")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summaries = try await SharingService.publishedWorkouts(ownerRecordName: user.ownerRecordName)
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }

    /// Download and plan first, confirm second — a payload that can't be read should
    /// fail before the user is asked to commit to anything.
    private func prepareDownload(_ summary: SharedWorkoutSummary) async {
        downloadingID = summary.id
        defer { downloadingID = nil }
        do {
            let payload = try await SharingService.download(summary)
            pendingPlan = try SharedWorkoutImporter.plan(payload, context: context)
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }

    private func performImport() {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        do {
            let workout = try SharedWorkoutImporter.importWorkout(plan, context: context)
            var message = "“\(workout.name)” is now in your workouts."
            if !plan.newExerciseNames.isEmpty {
                let count = plan.newExerciseNames.count
                message += " \(count) new exercise\(count == 1 ? " was" : "s were") added to your library."
            }
            infoMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
