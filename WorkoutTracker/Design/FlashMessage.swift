import SwiftUI

/// A brief message that appears, says one thing, and takes itself away — for answering a
/// tap that couldn't do what it looked like it would.
///
/// An `.alert` is this app's usual "here's why that didn't work" (`ExerciseDetailView`'s
/// blocked delete), but an alert demands a dismissal, and the answer here is one line the
/// user half-expects already. `MutualFollowBanner` has the self-dismissing shape this
/// wants but is bound to the sharing feature's own data, so this is the generic version.
///
/// Self-dismissal is `.task(id:)` rather than a scheduled closure: a new message cancels
/// and restarts the timer, and leaving the screen cancels it outright.
struct FlashMessage: View {
    /// The text plus a fresh identity per showing, so tapping the same row twice restarts
    /// the timer rather than inheriting what was left of the first tap's.
    struct Payload: Identifiable, Equatable {
        let id = UUID()
        let text: String

        init(_ text: String) { self.text = text }
    }

    let payload: Payload
    var onDismiss: () -> Void

    /// Long enough to read one line, short enough not to sit over what you're using.
    private static let visibleSeconds: Double = 2.5

    var body: some View {
        Text(payload.text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.appInk.opacity(0.92), in: Capsule())
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: payload.id) {
                try? await Task.sleep(for: .seconds(Self.visibleSeconds))
                guard !Task.isCancelled else { return }
                onDismiss()
            }
    }
}
