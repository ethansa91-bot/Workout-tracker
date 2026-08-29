import SwiftUI

/// Rest countdown — a normal tap starts/pauses/resumes it; it also auto-starts
/// (only if not already running) whenever the caller bumps `startSignal`, which
/// happens once per logged set; holding the button resets it back to full duration.
/// Bumping `stopSignal` force-stops and resets it regardless of running/paused
/// state — used when a max-hold-time stopwatch starts, since resting and holding
/// at the same time doesn't make sense.
struct RestTimerView: View {
    let totalSeconds: Int
    let soundProfile: TimerSoundProfile
    /// `session.status == .inProgress` — the timer freezes while the overall
    /// workout is paused, same as the step countdown in `TimeSessionRunnerView`.
    let isSessionActive: Bool
    @Binding var startSignal: Int
    @Binding var stopSignal: Int
    /// Drawn on the accent-filled header band rather than on the page background, so the
    /// panel drops its own surface and switches to white-on-green. Off keeps the
    /// original white card, for any caller placing the timer on the cream ground.
    var onAccent: Bool = false
    /// The band this sits in owns the height — it grows on iPad so the exercise name
    /// beside the timer can. Was a private constant the caller had to match by value.
    var height: CGFloat = RestTimerView.defaultHeight

    /// The displayed countdown. Authoritative while stopped; refreshed from `endsAt`
    /// on each tick while running.
    @State private var remainingSeconds: Int
    /// When the countdown reaches zero, or nil when it isn't running — which also makes
    /// this the single source of truth for "is it running".
    ///
    /// A wall-clock deadline rather than a per-tick decrement: the ticker stops while the
    /// app is backgrounded, so counting ticks meant locking the phone froze the rest timer
    /// and it picked up where it left off instead of catching up.
    @State private var endsAt: Date?
    /// Set when the overall workout pauses out from under a running countdown, so
    /// resuming the workout resumes the rest too rather than leaving it stopped.
    @State private var resumeWithSession = false

    init(totalSeconds: Int, soundProfile: TimerSoundProfile, isSessionActive: Bool, startSignal: Binding<Int>, stopSignal: Binding<Int>, onAccent: Bool = false, height: CGFloat = RestTimerView.defaultHeight) {
        self.totalSeconds = totalSeconds
        self.soundProfile = soundProfile
        self.isSessionActive = isSessionActive
        _startSignal = startSignal
        _stopSignal = stopSignal
        self.onAccent = onAccent
        self.height = height
        _remainingSeconds = State(initialValue: totalSeconds)
    }

    private var isRunning: Bool { endsAt != nil }

    /// Seconds left according to the clock, or the frozen display value when stopped.
    private func liveRemaining() -> Int {
        guard let endsAt else { return remainingSeconds }
        return max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up)))
    }

    /// The ring's depleting arc and the numerals: white on the accent band, where the
    /// green fill is itself the accent and an accent-colored ring would vanish into it.
    private var foreground: Color { onAccent ? .white : .primary }
    private var ringTint: Color { onAccent ? .white : Color.accentColor }
    private var trackTint: Color { onAccent ? .white.opacity(0.3) : Color.secondary.opacity(0.2) }
    private var captionTint: Color { onAccent ? .white.opacity(0.85) : .secondary }

    private static let cornerRadius: CGFloat = 16
    /// The compact header band's height, and the fallback for any caller that doesn't
    /// size the band itself.
    static let defaultHeight: CGFloat = 132
    private static let ringWidth: CGFloat = 6

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// How much rest is left, 0...1 — what the ring draws. Guarded so a zero total
    /// can't divide by zero.
    private var progress: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, CGFloat(remainingSeconds) / CGFloat(totalSeconds)))
    }

    /// The dial itself: a depleting ring with the remaining time at its centre.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(trackTint, lineWidth: Self.ringWidth)
            // A Circle trims cleanly along its own outline — a RoundedRectangle
            // doesn't, which is why an earlier version's arc spilled outside.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringTint,
                    style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)

            Text(timeString)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, Self.ringWidth + 4)
                .foregroundStyle(foreground)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var captions: some View {
        // Larger where there's room beside the ring; the compact layout keeps the small
        // type that fits under it.
        let isRegular = horizontalSizeClass == .regular
        return VStack(alignment: .center, spacing: 2) {
            Text(isRunning ? "Tap to pause" : "Tap to start")
                .font(isRegular ? .title3 : .subheadline)
                .foregroundStyle(captionTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !isRunning {
                Text("Hold to reset")
                    .font(isRegular ? .subheadline : .caption)
                    .foregroundStyle(captionTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
    }

    var body: some View {
        // A plain, non-Button view here — a Button's own tap gesture recognizer
        // reliably swallows the touch before a co-attached `.onLongPressGesture`
        // ever sees it, so long-press-to-reset silently never fired when this was
        // wrapped in a Button.
        Group {
            if horizontalSizeClass == .regular {
                // Wide enough to read side by side — the captions sit beside the ring
                // instead of stacking under it and squeezing its height.
                HStack(spacing: 12) {
                    ring
                        .padding(.leading, 5)
                    // Centered in whatever's left beside the ring, rather than pinned to
                    // its leading edge.
                    captions
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    ring
                    captions
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // Same surface as the set block beside it, so the header reads as two panels of
        // one screen rather than two different materials. On the accent band there is no
        // surface at all — the green is the surface, and a card here would break it up.
        .background {
            if !onAccent {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color.appSurface)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onTapGesture {
            toggle()
        }
        .onLongPressGesture(minimumDuration: 1) {
            guard !isRunning else { return }
            remainingSeconds = totalSeconds
        }
        // Only while actually counting down — the ticker used to run for the whole
        // session and discard the tick inside the handler, which is most of a workout
        // spent waking the run loop for nothing.
        .secondTicker(isActive: isRunning && isSessionActive) { tick() }
        .onChange(of: isSessionActive) { _, active in
            syncWithSession(isActive: active)
        }
        .onChange(of: totalSeconds) { _, newValue in
            remainingSeconds = newValue
            stop()
        }
        .onChange(of: startSignal) { _, _ in
            guard !isRunning else { return }
            remainingSeconds = totalSeconds
            start()
        }
        .onChange(of: stopSignal) { _, _ in
            remainingSeconds = totalSeconds
            stop()
        }
    }

    private func tick() {
        guard endsAt != nil else { return }
        let previous = remainingSeconds
        let current = liveRemaining()

        if current <= 0 {
            remainingSeconds = 0
            stop()
            SoundPlayer.playTimerComplete()
            return
        }

        guard current != previous else { return }
        remainingSeconds = current
        // Only on a normal one-second step. Coming back from a suspended app the
        // countdown jumps, and a warning beep for a threshold that passed while the
        // screen was off would land late and mean nothing.
        guard previous - current == 1 else { return }
        SoundPlayer.playWarningIfNeeded(remainingSeconds: current, profile: soundProfile)
    }

    private func start() {
        // A start signal that lands while the workout is paused is held until it
        // resumes — setting a deadline now would let the pause eat into the rest.
        guard isSessionActive else {
            resumeWithSession = true
            return
        }
        endsAt = Date.now.addingTimeInterval(Double(remainingSeconds))
    }

    private func stop() {
        endsAt = nil
        resumeWithSession = false
    }

    /// Pausing the workout freezes the rest countdown, and resuming it starts the
    /// countdown again from where it stopped — the deadline has to be rebased, or the
    /// time spent paused would be counted as rest.
    private func syncWithSession(isActive: Bool) {
        if isActive {
            guard resumeWithSession else { return }
            resumeWithSession = false
            start()
        } else {
            guard isRunning else { return }
            remainingSeconds = liveRemaining()
            endsAt = nil
            resumeWithSession = true
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func toggle() {
        if isRunning {
            remainingSeconds = liveRemaining()
            stop()
        } else {
            if remainingSeconds == 0 { remainingSeconds = totalSeconds }
            start()
        }
    }
}
