import AVFoundation

/// Which timer cues a run should play, carried as a value rather than read globally.
///
/// Replaces the old three-case `TimerSoundProfile`. That enum could only express "end
/// only" or "end plus a warning at 5 or 10 seconds"; the end tone itself was never
/// optional, and the warning mark was one of two hardcoded numbers. Both are free now,
/// which is what lets the beep and `TimeSessionRunnerView`'s spoken cue be timed against
/// each other instead of the voice being pinned to a separate hardcoded 10.
///
/// Still threaded through the runners as a value so a session can override it — see
/// `SessionRecapView`.
struct TimerCueSettings: Hashable {
    var endEnabled: Bool
    var warningEnabled: Bool
    var warningSeconds: Int

    static var fromSettings: TimerCueSettings {
        TimerCueSettings(
            endEnabled: AppSettings.soundEndEnabled,
            warningEnabled: AppSettings.soundWarningEnabled,
            warningSeconds: AppSettings.soundWarningSeconds
        )
    }

    /// Everything off, for a session the user has muted.
    static let silent = TimerCueSettings(endEnabled: false, warningEnabled: false, warningSeconds: 0)

    /// One line for the session menu: what these settings actually do, without reopening
    /// Settings to find out.
    var summary: String {
        switch (endEnabled, warningEnabled) {
        case (false, false): return "Off"
        case (true, false): return "At the end"
        case (false, true): return "\(warningSeconds)s warning only"
        case (true, true): return "\(warningSeconds)s warning + end"
        }
    }
}

/// Plays timer cues as an in-memory synthesized tone rather than a canned
/// `AudioServices` system sound — a system sound's duration and volume are fixed and
/// can't be adjusted, which isn't enough control for a single "done" tone that needs
/// to be both louder and noticeably longer than the short warning beep. Plays through
/// `AudioSessionController`, which owns the `.playback` category that makes cues
/// reliably audible mid-workout regardless of the silent switch.
enum SoundPlayer {
    private static let sampleRate: Double = 44100
    private static let toneFrequency: Double = 880
    /// A fifth above the end tone, so the warning is distinguishable by pitch and not
    /// just by rhythm — the two cues fire seconds apart and used to sound alike.
    private static let warningToneFrequency: Double = 1320
    private static let warningBeepDuration: TimeInterval = 0.08
    private static let warningBeepSpacing: TimeInterval = 0.12
    private static let completeBeepDuration: TimeInterval = 0.3
    /// The head-start tick keeps the old, slower beep length and the base pitch.
    private static let tickBeepDuration: TimeInterval = 0.15

    // Keeps strong references to in-flight players so ARC doesn't stop playback
    // partway through — nothing else on the caller side holds one.
    private static var activePlayers: Set<AVAudioPlayer> = []

    /// The three cues are fixed waveforms, so each is synthesized once and held for the
    /// life of the process.
    ///
    /// Not just an optimization. `AVAudioPlayer(data:)` makes no documented promise to
    /// copy the buffer it is handed, and the Swift `Data` → `NSData` bridge wraps rather
    /// than copies — so building a tone into a temporary freed that buffer while the
    /// player was still reading from it. The warning beep hit this on every fire: it
    /// starts a second player 0.12s in, and the closure holding the data is released
    /// the instant that player starts, leaving it reading ~7 KB of freed memory for the
    /// rest of its 0.08s. Intermittent only because it depends on the allocator reusing
    /// the region. Holding the tones here also keeps `tone`'s per-sample synthesis out
    /// of the timer tick, where it ran once per cue on the main thread.
    private static let warningToneData = SoundPlayer.tone(duration: warningBeepDuration, frequency: warningToneFrequency)
    private static let completeToneData = SoundPlayer.tone(duration: completeBeepDuration)
    private static let tickToneData = SoundPlayer.tone(duration: tickBeepDuration)

    /// The "timer's actually done" cue — a single tone, twice as long and played at
    /// full volume so it stands out from the shorter warning beep.
    ///
    /// Unconditional. Used where the tone isn't a *timer* ending: the head start's "go",
    /// and a hold reaching its previous best. Turning timer sounds off shouldn't silence
    /// the cue that tells you to start moving.
    static func playTimerComplete() {
        play(completeToneData)
    }

    /// The same tone, but only when the user wants a sound at zero.
    static func playTimerCompleteIfNeeded(cues: TimerCueSettings) {
        guard cues.endEnabled else { return }
        playTimerComplete()
    }

    /// A quick double beep, higher-pitched than the end tone, at the configured warning
    /// mark. The end cue is always played separately, by the caller, when the countdown
    /// actually reaches zero.
    static func playWarningIfNeeded(remainingSeconds: Int, cues: TimerCueSettings) {
        guard cues.warningEnabled, remainingSeconds == cues.warningSeconds else { return }
        playDoubleBeep()
    }

    /// One short tick per head-start second, before a max-hold-time stopwatch
    /// starts counting up. `playTimerComplete()` doubles as the "go" cue once the
    /// head start reaches zero.
    static func playHeadStartTick() {
        play(tickToneData)
    }

    private static func playDoubleBeep() {
        for i in 0..<2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * warningBeepSpacing) {
                play(warningToneData)
            }
        }
    }

    private static func play(_ data: Data) {
        guard let player = try? AVAudioPlayer(data: data) else { return }
        // Claimed before playback and released once the player is done, so the shared
        // session is only active while a cue is actually sounding — see
        // `AudioSessionController` for why this used to leak.
        let claim = AudioSessionController.beginActivity()
        player.volume = 1
        activePlayers.insert(player)
        player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1) {
            activePlayers.remove(player)
            AudioSessionController.endActivity(claim)
        }
    }

    /// Generates a sine-wave beep as in-memory 16-bit PCM WAV data, with a short
    /// fade in/out to avoid a click at the edges.
    private static func tone(duration: TimeInterval, frequency: Double = toneFrequency) -> Data {
        let frameCount = Int(sampleRate * duration)
        let fadeFrames = max(1, Int(sampleRate * 0.01))

        var pcmData = Data(capacity: frameCount * 2)
        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            var value = Float(sin(2 * .pi * frequency * t))
            if frame < fadeFrames {
                value *= Float(frame) / Float(fadeFrames)
            } else if frame > frameCount - fadeFrames {
                value *= Float(frameCount - frame) / Float(fadeFrames)
            }
            let sample = Int16(max(-1, min(1, value)) * Float(Int16.max))
            withUnsafeBytes(of: sample.littleEndian) { pcmData.append(contentsOf: $0) }
        }

        var header = Data()
        func appendString(_ s: String) { header.append(s.data(using: .ascii)!) }
        func appendUInt32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }

        let byteRate = UInt32(sampleRate) * 2
        let dataSize = UInt32(pcmData.count)

        appendString("RIFF")
        appendUInt32(36 + dataSize)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1)  // PCM
        appendUInt16(1)  // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(byteRate)
        appendUInt16(2)  // block align
        appendUInt16(16) // bits per sample
        appendString("data")
        appendUInt32(dataSize)

        return header + pcmData
    }
}
