import SwiftUI
import UIKit

/// Holds the display awake while a view is on screen — for the live session runner,
/// where the user is watching a timer or reading the next set from across the room and
/// never touches the screen long enough to defeat auto-lock.
private struct KeepScreenAwake: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = isActive }
            .onChange(of: isActive) { _, newValue in
                UIApplication.shared.isIdleTimerDisabled = newValue
            }
            // Always release on the way out. A stuck idle timer would keep the screen
            // awake — and the battery draining — long after the workout ended.
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func keepScreenAwake(_ isActive: Bool = true) -> some View {
        modifier(KeepScreenAwake(isActive: isActive))
    }
}
