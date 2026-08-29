import SwiftUI

/// The running workout clock, isolated into its own leaf view.
///
/// This used to be a `@State` string on `SessionRunnerView`, refreshed by a ticker there.
/// Every tick invalidated that view's body — which rebuilds the section runner with a
/// freshly allocated `onSectionComplete` closure, and a view holding a new closure never
/// compares equal — so SwiftUI could never skip the child and the entire rep/time runner
/// re-evaluated once a second for however many hours the session stayed open, dragging
/// its record lookups and media checks along with it. Owning the tick down here means
/// only this `Text` redraws.
///
/// Styling is left to the caller so the bar it sits in keeps its own typography.
struct ElapsedTimeLabel: View {
    let session: WorkoutSession

    @State private var text = "0:00:00"

    var body: some View {
        Text(text)
            .onAppear { refresh() }
            // A pause freezes the clock, so the displayed value has to be brought up to
            // date once more on the way into (and out of) the stopped state.
            .onChange(of: session.status) { _, _ in refresh() }
            .secondTicker(isActive: session.status == .inProgress) { refresh() }
    }

    private func refresh() {
        let total = Int(session.elapsedSeconds)
        text = String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
