import SwiftUI
import SwiftData

/// "Save what you held it at" — the post-workout card that turns a Follow Along step's
/// equipment into a personal record.
///
/// A Follow Along step runs for a fixed duration and logs no weight, so unlike the rep
/// runner there is nothing to promote automatically: the load only exists in the user's
/// head until they type it. That is why this is an explicit card at the end rather than a
/// silent `recordIfBest` mid-session.
///
/// Best-only, like every other record here: Save is disabled until the number beats what
/// is standing, so a lighter week can't quietly overwrite a heavier one.
struct FollowAlongRecordCard: View {
    let session: WorkoutSession
    let context: ModelContext

    @State private var drafts: [Candidate.ID: Double] = [:]
    @State private var saved: Set<Candidate.ID> = []

    /// One exercise + equipment + execution type performed in a Follow Along section, which
    /// is exactly the tuple a record is filed under.
    struct Candidate: Identifiable {
        struct ID: Hashable {
            let exercise: UUID
            let equipment: UUID
            let executionType: UUID?
        }

        let id: ID
        let exercise: Exercise
        let equipment: Equipment
        let executionType: ExecutionType?
        let title: String
        /// `TimeSectionStep.startingWeight` — nil unless the workout's builder set one.
        /// Only ever used by `prefill` when there's no personal record yet to use instead.
        let startingWeight: Double?
    }

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Records").font(.headline)
                Text("What you held these at. Saved only when it beats your best.")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                ForEach(candidates) { candidate in
                    row(candidate)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .cardStyle(cornerRadius: 14)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ candidate: Candidate) -> some View {
        let existing = record(for: candidate)
        let draft = drafts[candidate.id] ?? prefill(for: candidate, existing: existing)
        let options = candidate.equipment.sortedWeightCombos
        let canSave = PersonalRecordQueries.beats(
            record: existing,
            trackingMode: .maxHoldTime,
            reps: nil,
            weight: draft,
            holdSeconds: nil,
            isBodyweight: false,
            isFollowAlong: true
        )

        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.title)
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)

            HStack(spacing: 10) {
                Button {
                    step(candidate, delta: -1, from: draft, options: options)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.appAccent)

                Text(PersonalRecordFormatting.weight(draft, unit: candidate.equipment.effectiveWeightUnit, equipment: candidate.equipment))
                    .font(.subheadline)
                    .foregroundStyle(Color.appRust)
                    .monospacedDigit()
                    .frame(minWidth: 72)

                Button {
                    step(candidate, delta: 1, from: draft, options: options)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.appAccent)

                Spacer(minLength: 8)

                if saved.contains(candidate.id) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                } else {
                    Button("Save") { save(candidate, weight: draft, existing: existing) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .disabled(!canSave)
                }
            }

            if let existing, let best = existing.weight {
                Text("Best \(PersonalRecordFormatting.weight(best, unit: existing.weightUnit, equipment: existing.equipment))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Candidates

    /// Exercises actually performed in a Follow Along section this session, on named
    /// weighted equipment.
    ///
    /// Read through the step rather than from the log, because `StepLog` carries no
    /// equipment of its own — which also means editing the workout between finishing and
    /// tapping Done would change what this offers. Acceptable: the card is only on screen
    /// for the moments right after the session.
    private var candidates: [Candidate] {
        var seen = Set<Candidate.ID>()
        var result: [Candidate] = []
        for log in session.stepLogs.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard log.deletedAt == nil, log.outcome == .completed,
                  let step = log.timeSectionStep, step.stepType == .exercise,
                  let exercise = step.exercise,
                  let equipment = resolvedEquipment(for: step, exercise: exercise)
            else { continue }
            let executionType = PersonalRecordQueries.resolvedExecutionType(
                step.executionType ?? log.executionType, for: exercise
            )
            let id = Candidate.ID(exercise: exercise.id, equipment: equipment.id, executionType: executionType?.id)
            guard seen.insert(id).inserted else { continue }
            result.append(
                Candidate(
                    id: id,
                    exercise: exercise,
                    equipment: equipment,
                    executionType: executionType,
                    title: ExerciseNaming.title(exercise, side: step.side, executionType: step.executionType),
                    startingWeight: step.startingWeight
                )
            )
        }
        return result
    }

    /// The same resolution the rep runner's `chosenEquipment` performs: the step's own
    /// choice, then the catalog's, and always validated against the exercise's live
    /// weighted options so a stale reference can't file a record under nothing.
    private func resolvedEquipment(for step: TimeSectionStep, exercise: Exercise) -> Equipment? {
        guard !step.prefersBodyweight else { return nil }
        let options = exercise.weightedEquipmentOptions
        guard !options.isEmpty else { return nil }
        let id = step.preferredEquipment?.id ?? exercise.defaultWeightedEquipment?.id
        return options.first { $0.id == id } ?? options.first
    }

    private func record(for candidate: Candidate) -> PersonalRecord? {
        PersonalRecordQueries.current(
            for: candidate.exercise,
            equipment: candidate.equipment,
            executionType: candidate.executionType,
            trackingMode: .maxHoldTime,
            isBodyweight: false,
            isFollowAlong: true,
            context: context
        )
    }

    /// Where the stepper starts: what you last recorded, so an unchanged week is one tap
    /// on the plus and a Save. Failing that, the step's own configured starting weight
    /// (`TimeSectionStep.startingWeight`, set in the workout's settings panel), and only
    /// then the lightest thing the equipment offers.
    private func prefill(for candidate: Candidate, existing: PersonalRecord?) -> Double {
        if let weight = existing?.weight { return weight }
        return candidate.startingWeight ?? candidate.equipment.sortedWeightCombos.first?.value ?? 0
    }

    // MARK: - Editing

    private func step(_ candidate: Candidate, delta: Int, from current: Double, options: [WeightCombo]) {
        // Bodyweight is not a landing place here: a step with no load has no record to
        // set, so it never becomes a candidate in the first place. `.offerBodyweight`
        // can never come back with `allowsBodyweight: false`.
        guard case .weight(let value, _) = steppedSetWeight(
            delta: delta,
            weight: current,
            isBodyweight: false,
            options: options,
            allowsBodyweight: false
        ) else { return }
        drafts[candidate.id] = value
        saved.remove(candidate.id)
    }

    private func save(_ candidate: Candidate, weight: Double, existing: PersonalRecord?) {
        PersonalRecordQueries.setRecord(
            for: candidate.exercise,
            equipment: candidate.equipment,
            executionType: candidate.executionType,
            existing: existing,
            trackingMode: .maxHoldTime,
            reps: nil,
            weight: weight,
            // The step's duration belongs to the plan, not the achievement — keying on it
            // would strand the record the moment the step length changed.
            holdSeconds: nil,
            isBodyweight: false,
            isFollowAlong: true,
            weightUnit: candidate.equipment.effectiveWeightUnit,
            context: context
        )
        saved.insert(candidate.id)
    }
}
