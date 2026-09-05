import Foundation
import SwiftData

/// Keeps a published workout's public copy caught up with local edits, so "update the
/// shared version" doesn't depend on remembering to open Publish Workouts again.
///
/// Not actor-isolated itself — `Workout.markDirty()` calls into `scheduleIfPublished`
/// synchronously from whatever context edits a workout, which in this app is always the
/// main thread even where nothing formally enforces that. The publish work itself hops
/// onto the main actor explicitly, since `SharedWorkoutBuilder` requires it.
final class SharePublishScheduler {
    static let shared = SharePublishScheduler()

    /// One pending task per workout, keyed by id — a burst of edits to the same workout
    /// replaces its own timer rather than queuing a publish per edit.
    private var pending: [UUID: Task<Void, Never>] = [:]

    /// Long enough that a run of edits (adding a few exercises, adjusting several
    /// values) collapses into one publish; short enough that a follower's foreground
    /// sweep is unlikely to catch the workout mid-edit.
    private let debounceSeconds: Double = 4

    private init() {}

    func scheduleIfPublished(_ workout: Workout) {
        guard workout.isPublished else { return }
        let id = workout.id
        pending[id]?.cancel()
        pending[id] = Task { @MainActor [weak self, weak workout] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            // Re-checked after the sleep, not just at schedule time: the workout could
            // have been unpublished, deleted, or already carried by an even later edit
            // that rescheduled and superseded this task in the meantime.
            guard let workout, workout.isPublished, workout.deletedAt == nil else { return }
            let bundle = SharedWorkoutBuilder.makeBundle(for: workout)
            try? await SharingService.publish(bundle)
            self?.pending[id] = nil
        }
    }
}
