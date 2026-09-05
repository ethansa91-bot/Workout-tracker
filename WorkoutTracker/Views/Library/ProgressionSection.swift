import SwiftUI
import SwiftData

/// The "Progression" section on `ExerciseDetailView`: the ladder this exercise belongs to,
/// every rung's level, and the button that links another exercise into it.
///
/// Only offered here, on a saved exercise — a progression is a link between two catalog
/// rows, so there is nothing to link until the exercise exists. That is why this isn't a
/// closure-driven shared section the way `ExecutionTypeChipSection` is: it has one host.
///
/// Editing writes straight through and saves, matching the chip sections above it.
struct ProgressionSection: View {
    @Bindable var exercise: Exercise
    let context: ModelContext

    @State private var showingPicker = false

    /// Every live rung in the store, so the picker can tell at a glance which exercises are
    /// already spoken for. One query rather than reading `Exercise.progressionGroup` per
    /// row: that walks `progressionSteps → group` on every render, once per catalog entry.
    @Query private var allProgressionSteps: [ProgressionStep]

    private var group: ProgressionGroup? { exercise.progressionGroup }
    private var steps: [ProgressionStep] { group?.sortedSteps ?? [] }

    /// exercise id → the ladder it is on.
    private var ladderByExerciseID: [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for step in allProgressionSteps {
            guard step.deletedAt == nil,
                  let exerciseID = step.exercise?.id,
                  let group = step.group, group.deletedAt == nil
            else { continue }
            result[exerciseID] = group.id
        }
        return result
    }

    /// Why an exercise can't join this ladder, or nil when it can. An exercise belongs to
    /// at most one progression, which is what makes "level up" answerable — so `link` has
    /// always dropped these, silently. This is that same rule, said out loud.
    private func ineligibleReason(_ candidate: Exercise) -> String? {
        guard let ladderID = ladderByExerciseID[candidate.id] else { return nil }
        return ladderID == group?.id ? "In this progression" : "In another progression"
    }

    var body: some View {
        Section {
            ForEach(steps) { step in
                row(step)
            }

            if !exercise.orphanedProgressionSteps.isEmpty {
                Button {
                    clearOrphans()
                } label: {
                    Label("Clear broken progression links", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.appDanger)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .padding(.horizontal, HeaderMetrics.bandHorizontalInset)
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.appSurface)
                .listRowSeparator(.hidden)
            }

            Button {
                showingPicker = true
            } label: {
                Label(steps.isEmpty ? "Link an exercise" : "Add an exercise to progression", systemImage: "plus")
                    .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
            // Matches the rows above it in size and gutter — without the font it inherits
            // the list's `.body` and reads larger than the ladder it belongs to.
            .font(.subheadline)
            .padding(.horizontal, HeaderMetrics.bandHorizontalInset)
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.appSurface)
            .listRowSeparator(.hidden)
            .sheet(isPresented: $showingPicker) {
                MultiExercisePickerView(
                    // Marked rather than hidden, so the ladder reads as a whole while
                    // you're adding to it.
                    existingExerciseIDs: Set(steps.compactMap { $0.exercise?.id }),
                    // The one exercise that is never a candidate: it is the ladder's
                    // anchor, so offering it at all is noise.
                    excluding: [exercise.id],
                    ineligible: ineligibleReason,
                    initialFilter: ExerciseFilter()
                ) { picked in
                    link(picked)
                }
            }
        } header: {
            ListBandHeader(title: "Progression")
        } footer: {
            FormSectionFooter(footerText)
        }
    }

    private var footerText: String {
        guard let group, steps.count > 1 else {
            return "Link the easier and harder versions of this exercise — inverted row, band-assisted pull-up, pull-up. During a workout you can move between them, and the next one starts at the highest level you've logged. An exercise can only be on one progression, so anything already on another is offered but not selectable."
        }
        return "Reached level \(group.reachedLevel) of \(group.maxLevel). Two exercises can share a level when they're alternatives rather than a step up."
    }

    // MARK: - Rows

    /// One line: name, the level between the ± that step it, and the unlink.
    ///
    /// No `Stepper` and no `NumberBadge` — a `Stepper` keeps a ~32pt intrinsic height even
    /// with `.labelsHidden()`, and it was the floor under every row. Plain buttons have no
    /// such floor, which is what lets a five-rung ladder read as a list rather than a stack
    /// of cards.
    private func row(_ step: ProgressionStep) -> some View {
        let isThisExercise = step.exercise?.id == exercise.id
        return HStack(spacing: 8) {
            Text(step.exercise?.displayName ?? "Exercise")
                .fontWeight(isThisExercise ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button {
                setLevel(step, to: step.level - 1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(step.level <= 1)

            Text("Level \(step.level)")
                .font(.subheadline)
                .foregroundStyle(Color.appRust)
                .monospacedDigit()

            Button {
                setLevel(step, to: step.level + 1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(step.level >= 20)

            Button {
                unlink(step)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.appDanger)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 4)
        }
        .font(.subheadline)
        // The band's own inset, not a text row's 16 — these rows sit directly under the
        // "Progression" header and any other value reads as a misalignment against it.
        .padding(.horizontal, HeaderMetrics.bandHorizontalInset)
        .padding(.vertical, 6)
        // The tint stays on the content, not on `listRowBackground`, which is white for
        // every row — painting it there would cover the highlight instead of backing it.
        .background(isThisExercise ? Color.appAccent.opacity(0.10) : Color.clear)
        // Zeroed insets, or the plain list keeps its own padding around the row and the
        // band ends up taller than what it contains. `fullBleedList` drops the 44pt
        // minimum but not the insets.
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.appSurface)
        // `fullBleedRow`'s separator recipe at this section's gutter: drawn by the list's
        // own chrome, so the hairline costs no height. Its own 16pt guides would sit left
        // of the rows they divide, which is why the guides are restated here.
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(Color.appHairline)
        .alignmentGuide(.listRowSeparatorLeading) { _ in HeaderMetrics.bandHorizontalInset }
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
    }

    private func setLevel(_ step: ProgressionStep, to newValue: Int) {
        step.level = min(20, max(1, newValue))
        step.markDirty()
        group?.markDirty()
        try? context.save()
    }

    // MARK: - Editing

    /// Rungs whose ladder no longer exists. They render nowhere and `unlink` can't reach
    /// them, but they still show up as a reference that blocks deleting the exercise —
    /// so this is the only way out of that state short of a full data reset.
    private func clearOrphans() {
        for step in exercise.orphanedProgressionSteps {
            SyncDeletion.delete(step, context: context)
        }
        exercise.markDirty()
        try? context.save()
    }

    /// Adds the picked exercises to this exercise's ladder, creating one if there isn't
    /// yet a ladder to add to.
    ///
    /// An exercise belongs to at most one progression, which is what makes "level up"
    /// answerable — so anything already on a *different* ladder is skipped rather than
    /// moved. Picking one that is already on this ladder is a no-op for the same reason.
    private func link(_ picked: [Exercise]) {
        let candidates = picked.filter { $0.id != exercise.id && $0.progressionGroup == nil }
        guard !candidates.isEmpty || group == nil else { return }

        let target: ProgressionGroup
        if let group {
            target = group
        } else {
            guard !candidates.isEmpty else { return }
            let created = ProgressionGroup()
            context.insert(created)
            // This exercise anchors the new ladder at level 1 — it is the one being
            // edited, so it is what the levels are being chosen relative to.
            context.insert(ProgressionStep(group: created, exercise: exercise, level: 1))
            target = created
        }

        var nextLevel = (target.sortedSteps.map(\.level).max() ?? 0) + 1
        for candidate in candidates {
            context.insert(ProgressionStep(group: target, exercise: candidate, level: nextLevel))
            nextLevel += 1
        }
        target.markDirty()
        exercise.markDirty()
        try? context.save()
    }

    /// Removes one rung, and the whole ladder once fewer than two remain — a progression
    /// of one is not a progression, and leaving it would keep offering a picker with a
    /// single entry.
    private func unlink(_ step: ProgressionStep) {
        guard let group else { return }
        SyncDeletion.delete(step, context: context)

        if group.sortedSteps.count < 2 {
            for remaining in group.sortedSteps {
                SyncDeletion.delete(remaining, context: context)
            }
            SyncDeletion.delete(group, context: context)
        }
        group.markDirty()
        exercise.markDirty()
        try? context.save()
    }
}
