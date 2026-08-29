import SwiftUI
import SwiftData

/// Someone's published workouts, with the option to save one or several into your own
/// library.
struct FollowedUserDetailView: View {
    let user: FollowedUser

    @Environment(\.modelContext) private var context
    @Query private var localWorkouts: [Workout]

    @State private var summaries: [SharedWorkoutSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    /// Decoded and checked against the local catalog before the user is asked to
    /// confirm — nothing is written until they do.
    @State private var pendingPlan: SharedWorkoutPlan?
    /// Presented when the plan has something to decide. A plan where everything already
    /// matches skips this entirely and goes straight to a one-tap confirmation.
    @State private var reviewPlan: SharedWorkoutPlan?
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var isDownloading = false
    @State private var showingResaveConfirm = false

    /// The publisher's workout ids this library already holds a copy of.
    ///
    /// `SharedWorkoutImporter.buildWorkout` stamps `clonedFromWorkoutId` with the
    /// publisher's workout id, and a summary carries that same id — so the two line up
    /// without any new field or CloudKit schema change. The field is dual-purpose
    /// (`WorkoutCloningService` sets it to a *local* workout's id when duplicating), so a
    /// false positive would need an actual UUID collision.
    private var savedSourceIDs: Set<UUID> {
        Set(localWorkouts.lazy.filter { $0.deletedAt == nil }.compactMap(\.clonedFromWorkoutId))
    }

    /// Unsaved first, then already-saved, each newest first — what you haven't got yet is
    /// the reason you opened this screen.
    private var orderedSummaries: [SharedWorkoutSummary] {
        let saved = savedSourceIDs
        return summaries.sorted { lhs, rhs in
            let lhsSaved = saved.contains(lhs.workoutID)
            let rhsSaved = saved.contains(rhs.workoutID)
            if lhsSaved != rhsSaved { return !lhsSaved }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private var selectedSummaries: [SharedWorkoutSummary] {
        orderedSummaries.filter { selection.contains($0.id) }
    }

    private var alreadySavedSelectionCount: Int {
        let saved = savedSourceIDs
        return selectedSummaries.count { saved.contains($0.workoutID) }
    }

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
                let rows = orderedSummaries
                let saved = savedSourceIDs
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, summary in
                    row(for: summary, isSaved: saved.contains(summary.workoutID))
                        .fullBleedRow(isLast: index == rows.count - 1)
                }
            }
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) { PushedTitleBand(title: user.resolvedDisplayName) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !summaries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                    .disabled(isDownloading)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { selectionAction }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $reviewPlan) { plan in
            SharedImportReviewView(plan: plan) { reviewed in
                performImport(reviewed)
            }
        }
        .alert("Save again?", isPresented: $showingResaveConfirm) {
            Button("Save Again") { Task { await prepareDownload(selectedSummaries) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(resaveMessage)
        }
        .alert("Save this workout?", isPresented: Binding(
            get: { pendingPlan != nil },
            set: { if !$0 { pendingPlan = nil } }
        )) {
            Button("Save") {
                if let plan = pendingPlan {
                    pendingPlan = nil
                    performImport(plan)
                }
            }
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

    // MARK: - Rows

    @ViewBuilder
    private func row(for summary: SharedWorkoutSummary, isSaved: Bool) -> some View {
        Button {
            if isSelecting {
                toggle(summary)
            } else {
                start([summary], isSaved: isSaved)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selection.contains(summary.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(summary.id) ? Color.appAccent : Color.appInkMuted)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.name).foregroundStyle(Color.appInk)
                    HStack(spacing: 6) {
                        Text(subtitle(for: summary))
                            .font(.caption)
                            .foregroundStyle(Color.appInkMuted)
                        if isSaved {
                            StatusPill(text: "Saved", icon: "checkmark", tint: Color.appAccent)
                        }
                    }
                }

                Spacer(minLength: 8)

                if !isSelecting {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
    }

    @ViewBuilder
    private var selectionAction: some View {
        if isSelecting && !selection.isEmpty {
            Button {
                start(selectedSummaries, isSaved: alreadySavedSelectionCount > 0)
            } label: {
                Group {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Text("Save \(selection.count) Workout\(selection.count == 1 ? "" : "s")")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.appAccent.opacity(0.25))
            .foregroundStyle(Color.appAccent)
            .disabled(isDownloading)
            .padding()
            .background(.thickMaterial)
        }
    }

    // MARK: - Actions

    private func toggle(_ summary: SharedWorkoutSummary) {
        if selection.contains(summary.id) {
            selection.remove(summary.id)
        } else {
            selection.insert(summary.id)
        }
    }

    /// Saving something already in the library is legitimate — it's how you pick up a
    /// publisher's changes — but it adds a copy rather than replacing one the user may
    /// have edited or already trained, so it asks first.
    private func start(_ chosen: [SharedWorkoutSummary], isSaved: Bool) {
        guard !chosen.isEmpty else { return }
        if isSaved {
            selection = Set(chosen.map(\.id))
            showingResaveConfirm = true
        } else {
            Task { await prepareDownload(chosen) }
        }
    }

    private var resaveMessage: String {
        let count = alreadySavedSelectionCount
        let subject = count == 1 ? "One of these is" : "\(count) of these are"
        return "\(subject) already in your library. Saving again adds a separate copy — the ones you already have aren't changed."
    }

    private func subtitle(for summary: SharedWorkoutSummary) -> String {
        let sections = "\(summary.sectionCount) Section\(summary.sectionCount == 1 ? "" : "s")"
        return summary.summary.isEmpty ? sections : "\(sections) · \(summary.summary)"
    }

    /// Only reached when the plan has nothing to decide — every catalog row the workouts
    /// touch already matches something identical, so there is no review to show.
    private var confirmationMessage: String {
        guard let plan = pendingPlan else { return "" }
        let subject = plan.workoutCount == 1 ? "“\(plan.displayTitle)”" : plan.displayTitle
        return "\(subject) will be saved to your workouts. Everything used is already in your library, so nothing is added or changed."
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
    private func prepareDownload(_ chosen: [SharedWorkoutSummary]) async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            var bundles: [SharedWorkoutBundle] = []
            for summary in chosen {
                bundles.append(try await SharingService.download(summary))
            }

            let plan = try SharedWorkoutImporter.plan(bundles, context: context)
            // A review screen with nothing on it is friction, not safety. When every
            // incoming row already matches something identical, go straight to the
            // one-tap confirmation instead.
            if plan.needsReview {
                reviewPlan = plan
            } else {
                pendingPlan = plan
            }
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription
                ?? CloudKitErrorFormatter.describe(error)
        }
    }

    private func performImport(_ plan: SharedWorkoutPlan) {
        do {
            let workouts = try SharedWorkoutImporter.importWorkouts(plan, context: context)
            isSelecting = false
            selection.removeAll()

            var message = workouts.count == 1
                ? "“\(workouts[0].name)” is now in your workouts."
                : "\(workouts.count) workouts are now in your workouts."
            let added = plan.catalog.newExerciseNames.count
            if added > 0 {
                message += " \(added) new exercise\(added == 1 ? " was" : "s were") added to your library."
            }
            infoMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
