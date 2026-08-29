import AVFoundation

/// The single owner of `AVAudioSession` for the whole app.
///
/// Both cue sources — `SoundPlayer`'s timer beeps and `SpeechAnnouncer`'s spoken steps —
/// used to configure and activate the shared session themselves, with different option
/// sets, and neither ever deactivated it. Two consequences: the category was rewritten
/// twice within a single timer tick at the ten-second mark (where a beep and a cue fire
/// back to back), and one beep left the session active for the rest of the process, so
/// `.duckOthers` held the user's music dipped indefinitely and the audio route stayed
/// powered through a multi-hour workout.
///
/// Callers now bracket their playback with `beginActivity()`/`endActivity()` instead. The
/// category is set once, and the session is released shortly after the last cue finishes.
@MainActor
enum AudioSessionController {
    /// `.duckOthers` alongside `.mixWithOthers` so background music dips under a cue
    /// instead of stopping. Applied to beeps as well as speech now that both share one
    /// category — with deactivation in place the dip lasts only as long as the cue.
    private static let options: AVAudioSession.CategoryOptions = [.mixWithOthers, .duckOthers]

    private static var isConfigured = false
    private static var isActive = false
    private static var activityCount = 0
    /// Bumped on every `endActivity()`; a pending deactivation that no longer matches
    /// has been superseded by a newer cue and does nothing.
    private static var deactivationGeneration = 0

    /// How long to wait after the last cue before releasing the session. Long enough to
    /// span the gap between a warning beep and the spoken cue that follows it, so a
    /// single announcement doesn't deactivate and reactivate mid-sentence.
    private static let idleDeactivationDelay: TimeInterval = 1.5

    /// Sets the category ahead of the first cue, so the initial `beginActivity()` isn't
    /// the thing that pays for it — configuring the session inline is one of the classic
    /// causes of a clipped first word.
    static func prewarm() {
        configureIfNeeded()
    }

    private static func configureIfNeeded() {
        guard !isConfigured else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: options)
        isConfigured = true
    }

    /// Claims the session for one cue. Balanced by exactly one `endActivity()`.
    static func beginActivity() {
        activityCount += 1
        // Invalidate any deactivation scheduled while the count was at zero.
        deactivationGeneration += 1
        configureIfNeeded()
        // Activated on every claim rather than skipped when the flag says it's already
        // active: an interruption (a phone call, say) deactivates the session without
        // telling us, and a cached flag would leave the next cue silent. It's a cheap
        // no-op when the session really is active — setting the *category* is the
        // expensive part, and that now happens once.
        try? AVAudioSession.sharedInstance().setActive(true)
        isActive = true
    }

    /// Releases one cue's claim. When the last one drops, the session is deactivated
    /// after a short idle delay.
    static func endActivity() {
        guard activityCount > 0 else { return }
        activityCount -= 1
        guard activityCount == 0 else { return }

        deactivationGeneration += 1
        let generation = deactivationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + idleDeactivationDelay) {
            guard generation == deactivationGeneration, activityCount == 0 else { return }
            deactivate()
        }
    }

    /// Drops the session immediately, whatever is outstanding — for leaving the runner
    /// or backgrounding the app, where waiting out the idle delay serves no one.
    static func deactivateNow() {
        activityCount = 0
        deactivationGeneration += 1
        deactivate()
    }

    /// `.notifyOthersOnDeactivation` so whatever was ducked returns to full volume
    /// rather than staying dipped until it next changes tracks.
    private static func deactivate() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }
}
