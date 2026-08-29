import Foundation
import Observation

/// Carries sharing events from outside the view tree into it.
///
/// Two things arrive from places a view can't observe directly: a `workouttracker://`
/// link handled by the scene, and the result of the reciprocal-follow sweep that runs on
/// foreground. Both need to surface at tab-root level rather than inside Settings →
/// Sharing, because a link should work whichever tab the user happens to be on.
@Observable
@MainActor
final class SharingRouter {
    static let shared = SharingRouter()

    /// A share code from an opened link, waiting to be presented.
    var pendingFollow: PendingFollow?

    /// Rows the last sweep created, for the "X followed you" notice. Cleared when the
    /// notice is dismissed or undone.
    var newMutualFollows: [FollowedUser] = []

    /// Why the last reciprocation sweep couldn't run, if it couldn't.
    ///
    /// Kept rather than shown: the sweep is unprompted, so this surfaces quietly in the
    /// Sharing screen's setup check instead of interrupting. Before this existed a
    /// rejected query was indistinguishable from having no followers, which is exactly
    /// how a missing CloudKit index went unnoticed.
    var lastSweepFailure: Error?

    private init() {}

    /// Identifiable so it can drive `.sheet(item:)` — a bare `String?` can't.
    struct PendingFollow: Identifiable, Equatable {
        let code: String
        var id: String { code }
    }

    /// Returns true when the URL was one of ours, so the scene can ignore anything else.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        switch ShareLinkURL.parse(url) {
        case .follow(let code):
            pendingFollow = PendingFollow(code: code)
            return true
        case nil:
            return false
        }
    }
}
