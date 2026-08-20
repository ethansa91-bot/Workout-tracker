import Foundation

/// The one place the CloudKit container identifier is written down. It must match the
/// `com.apple.developer.icloud-container-identifiers` entry in
/// `WorkoutTracker.entitlements` character-for-character — note the lowercase `w` in
/// the middle component and the capital `W` in the last one.
enum CloudKitContainer {
    static let identifier = "iCloud.com.ethanwiniger.workoutTracker.WorkoutTracker"
}

/// Whether the app's `ModelContainer` actually came up with CloudKit attached, or
/// silently fell back to a local-only store (see `WorkoutTrackerApp.sharedModelContainer`).
///
/// This distinction is invisible at runtime otherwise — a container that failed to
/// reach CloudKit behaves exactly like one that is simply slow to sync — so it's the
/// single most useful thing `SyncDiagnosticsView` can report.
enum ContainerStatus {
    private(set) nonisolated(unsafe) static var isCloudEnabled = false
    /// The error that forced the local-only fallback, kept so diagnostics can show a
    /// real reason instead of a bare "unavailable".
    private(set) nonisolated(unsafe) static var failure: NSError?

    /// Called exactly once, from the container-creation closure, before any UI exists.
    static func record(isCloudEnabled: Bool, failure: NSError?) {
        self.isCloudEnabled = isCloudEnabled
        self.failure = failure
    }
}
