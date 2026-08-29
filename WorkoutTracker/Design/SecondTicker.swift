import Combine
import SwiftUI

/// Owns the run-loop timer behind `secondTicker`. A class, so the modifier can swap in
/// the current tick handler on every re-render without tearing the timer down and
/// rebuilding it.
@MainActor
private final class TickerBox {
    /// Reassigned each render, so a running timer never calls into a closure captured
    /// from an earlier pass.
    var action: () -> Void = {}
    private var cancellable: AnyCancellable?

    func start() {
        guard cancellable == nil else { return }
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.action() }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}

private struct SecondTickerModifier: ViewModifier {
    let isActive: Bool
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    // Must be @State: a plain property would be a fresh box on every re-render, so the
    // timer would rarely survive long enough to fire.
    @State private var box = TickerBox()

    /// Backgrounding stops the tick on its own, rather than leaving the run loop being
    /// woken until iOS gets around to suspending the process. `.inactive` — an app
    /// switcher glance, a pulled-down notification banner — deliberately keeps running:
    /// those last a moment, and a count-up stopwatch shouldn't lose seconds to them.
    private var shouldRun: Bool { isActive && scenePhase != .background }

    func body(content: Content) -> some View {
        // Writing through the box doesn't invalidate anything, so this is safe here and
        // guarantees the handler is current whenever the next tick lands.
        box.action = action
        return content
            .onAppear { sync() }
            .onDisappear { box.stop() }
            .onChange(of: shouldRun) { _, _ in sync() }
    }

    private func sync() {
        if shouldRun { box.start() } else { box.stop() }
    }
}

extension View {
    /// A once-per-second tick that runs only while `isActive` and the app is foregrounded.
    ///
    /// The session runners used to hold an always-on `Timer.publish(...).autoconnect()` and
    /// guard *inside* the handler instead, so a paused workout — or a rest timer sitting
    /// at rest, which is most of a workout — still woke the main run loop and triggered a
    /// SwiftUI invalidation check every second for the hours a session can stay open.
    /// `.common` mode meant they kept firing during scrolling, too.
    func secondTicker(isActive: Bool, action: @escaping () -> Void) -> some View {
        modifier(SecondTickerModifier(isActive: isActive, action: action))
    }
}
