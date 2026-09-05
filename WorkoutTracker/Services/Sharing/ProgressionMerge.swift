import Foundation
import SwiftData

/// Applies the progression half of a download, after `CatalogMerge` has resolved which
/// local exercise each incoming one landed on.
///
/// **The invariant this exists to protect: an exercise is on at most one ladder.**
/// `Exercise.progressionStep` takes `.first` of an unordered relationship, so two ladders
/// make `progressionGroup`, `progressionLevel` and every reader of them non-deterministic
/// — including `RepSessionRunnerView.resolvedExercise`, which would then swap the exercise
/// being performed and log the swap. Every path below either upholds the invariant or
/// imports nothing.
@MainActor
enum ProgressionMerge {

    /// `steps` is every bundle's rungs folded together and deduped — see the call site
    /// for why this runs once rather than per bundle.
    static func apply(
        _ plan: ProgressionImportPlan,
        steps allSteps: [ArchiveProgressionStep],
        exercises: [UUID: Exercise],
        context: ModelContext
    ) {
        guard !plan.isEmpty else { return }
        let stepsByGroup = Dictionary(grouping: allSteps, by: { $0.groupID })

        for decision in plan.decisions where decision.resolution != .keepMine {
            let steps = (stepsByGroup[decision.incomingID] ?? []).sorted { $0.level < $1.level }

            // Resolve each rung to a local exercise, dropping any that didn't survive the
            // catalog merge. A rung pointing at nothing is the orphan state that used to
            // make an exercise undeletable, so it is never created.
            var rungs: [(exercise: Exercise, level: Int)] = []
            for step in steps {
                guard let incomingID = step.exerciseID,
                      let exercise = exercises[incomingID]
                else { continue }
                rungs.append((exercise, step.level))
            }

            switch decision.resolution {
            case .keepMine:
                continue

            case .nonConflictingOnly:
                // Anything already laddered stays where it is; the rest form the import.
                rungs = rungs.filter { $0.exercise.progressionGroup == nil }

            case .useTheirs:
                // Dismantle the local ladders first. Adding on top would put an exercise
                // on two at once, which is the one state nothing downstream survives.
                let localGroups = Set(rungs.compactMap { $0.exercise.progressionGroup?.id })
                for rung in rungs {
                    guard let group = rung.exercise.progressionGroup,
                          localGroups.contains(group.id)
                    else { continue }
                    for step in group.sortedSteps {
                        SyncDeletion.delete(step, context: context)
                    }
                    SyncDeletion.delete(group, context: context)
                }
            }

            // Belt and braces: whatever the branch above decided, never attach an exercise
            // that is still on a live ladder.
            rungs = rungs.filter { $0.exercise.progressionGroup == nil }

            // A single rung is not a progression, and a group holding one would offer a
            // menu with nothing to choose.
            guard rungs.count > 1 else { continue }

            // `reachedLevel: 1` — the publisher writes 1 too, but this is where it
            // actually matters: the recipient has performed none of these rungs, and
            // anything higher would auto-advance them to one they've never done.
            let group = ProgressionGroup(reachedLevel: 1)
            context.insert(group)
            for rung in rungs {
                context.insert(ProgressionStep(group: group, exercise: rung.exercise, level: rung.level))
            }
        }
    }
}
