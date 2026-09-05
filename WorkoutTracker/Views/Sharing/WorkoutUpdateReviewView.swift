import SwiftUI
import SwiftData

/// The "another merger system to see the change" screen: what a followed workout's
/// re-publish changed, one row per field or structural change, each defaulting to "take
/// theirs" and individually switchable to "keep mine."
///
/// Three phases, walked in order:
/// 1. Download + catalog planning (`.loading`) — silent unless it fails or the publisher's
///    record is gone.
/// 2. Catalog review, only when the update references something new — reuses
///    `SharedImportReviewView` exactly as a fresh save does, since a new exercise or piece
///    of equipment needs the same decision either way.
/// 3. The diff itself (`.diff`), where accepting applies in place for an unlocked workout
///    or offers a fresh copy for a locked one — `Workout.isLocked`'s existing rule.
struct WorkoutUpdateReviewView: View {
    let workout: Workout
    /// Called once the sheet has nothing further to show for this workout — applied,
    /// saved as a copy, or dismissed outright — so the caller can drop it from
    /// `SharingRouter.updatedFollowedWorkouts`.
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case unavailable
        case diff([WorkoutDifference])
        case applied(String)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var updatePlan: WorkoutUpdateService.UpdatePlan?
    @State private var catalogReviewPlan: SharedWorkoutPlan?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    ContentUnavailableView(
                        "No Longer Available",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("This workout is no longer published, or the update was withdrawn.")
                    )
                case .diff(let differences):
                    diffList(differences)
                case .applied(let message):
                    ContentUnavailableView("Updated", systemImage: "checkmark.circle.fill", description: Text(message))
                case .failed(let message):
                    ContentUnavailableView("Couldn't Update", systemImage: "exclamationmark.triangle", description: Text(message))
                }
            }
            .navigationTitle("Workout Updated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onFinished()
                        dismiss()
                    }
                }
            }
            .sheet(item: $catalogReviewPlan) { plan in
                SharedImportReviewView(plan: plan) { decidedPlan in
                    catalogReviewPlan = nil
                    updatePlan?.catalogPlan = decidedPlan
                    computeDiff()
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func diffList(_ differences: [WorkoutDifference]) -> some View {
        List {
            if differences.isEmpty {
                Section {
                    Text("Nothing changed since you saved this workout.")
                        .foregroundStyle(Color.appInkMuted)
                }
            } else {
                Section {
                    ForEach(differences.indices, id: \.self) { index in
                        differenceRow(differences[index])
                    }
                } header: {
                    Text(WorkoutDifferenceCalculator.isSettingsOnly(differences) ? "This update only changes settings" : "What Changed")
                } footer: {
                    Text("Each change defaults to using the publisher's version. Turn one off to keep what you have instead.")
                }
            }

            if workout.isLocked {
                Section {
                    Text("This copy has already been used in a session, so it can't be changed in place. Save the update as a new copy instead.")
                        .foregroundStyle(Color.appInkMuted)
                    Button {
                        saveAsCopy()
                    } label: {
                        if isWorking { ProgressView() } else { Text("Save as New Copy") }
                    }
                    .disabled(isWorking)
                }
            } else if !differences.isEmpty {
                Section {
                    Button {
                        applyInPlace(differences)
                    } label: {
                        if isWorking { ProgressView() } else { Text("Apply Update") }
                    }
                    .disabled(isWorking)
                }
            }
        }
        .themedListBackground()
    }

    private func differenceRow(_ difference: WorkoutDifference) -> some View {
        let binding = Binding<Bool>(
            get: { difference.takeTheirs },
            set: { newValue in setTakeTheirs(newValue, for: difference) }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 4) {
                Text(difference.field)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appInk)
                comparisonLine("Yours", difference.mine, isChosen: !difference.takeTheirs)
                comparisonLine("Theirs", difference.theirs, isChosen: difference.takeTheirs)
            }
        }
        .tint(Color.appAccent)
    }

    private func comparisonLine(_ side: String, _ value: String, isChosen: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(side)
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(isChosen ? Color.appInk : Color.appInkMuted)
                .strikethrough(!isChosen, color: Color.appInkMuted)
        }
    }

    private func setTakeTheirs(_ newValue: Bool, for difference: WorkoutDifference) {
        guard case .diff(var differences) = phase,
              let index = differences.firstIndex(where: { $0.id == difference.id })
        else { return }
        differences[index].takeTheirs = newValue
        phase = .diff(differences)
    }

    // MARK: - Actions

    private func load() async {
        do {
            guard let plan = try await WorkoutUpdateService.preparePlan(for: workout, context: context) else {
                phase = .unavailable
                return
            }
            updatePlan = plan
            if plan.catalogPlan.needsReview {
                catalogReviewPlan = plan.catalogPlan
            } else {
                computeDiff()
            }
        } catch {
            phase = .failed((error as? SharingError)?.errorDescription ?? CloudKitErrorFormatter.describe(error))
        }
    }

    private func computeDiff() {
        guard let plan = updatePlan else { return }
        let differences = WorkoutUpdateService.computeDiff(plan, context: context)
        // A re-publish with nothing that actually differs — e.g. touched and reverted.
        // Stamping `sourceUpdatedAt` here, with nothing to apply and no catalog touched,
        // is what stops this workout re-appearing as "updated" on every later sweep.
        guard !differences.isEmpty else {
            workout.sourceUpdatedAt = plan.bundle.sourceUpdatedAt
            workout.markDirty()
            try? context.save()
            phase = .applied("“\(workout.name)” is already up to date.")
            onFinished()
            return
        }
        phase = .diff(differences)
    }

    private func applyInPlace(_ differences: [WorkoutDifference]) {
        guard let plan = updatePlan else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try WorkoutUpdateService.applyInPlace(differences, to: workout, plan: plan, context: context)
            phase = .applied("“\(workout.name)” is up to date.")
            onFinished()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func saveAsCopy() {
        guard let plan = updatePlan else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let copy = try WorkoutUpdateService.saveAsCopy(plan, context: context)
            phase = .applied("“\(copy.name)” was added as a new copy with the update.")
            onFinished()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
