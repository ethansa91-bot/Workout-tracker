import AVFoundation

enum TimerSoundProfile: String, CaseIterable, Identifiable, Codable {
    case endOnly, warn5, warn10

    var id: String { rawValue }

    var label: String {
        switch self {
        case .endOnly: return "At the end"
        case .warn5: return "5s warning + end"
        case .warn10: return "10s warning + end"
        }
    }
}

/// Plays timer cues as an in-memory synthesized tone rather than a canned
/// `AudioServices` system sound — a system sound's duration and volume are fixed and
/// can't be adjusted, which isn't enough control for a single "done" tone that needs
/// to be both louder and noticeably longer than the short warning beep. Uses the
/// `.playback` session category so it's reliably audible mid-workout regardless of
/// the silent switch.
enum SoundPlayer {
    private static let sampleRate: Double = 44100
    private static let toneFrequency: Double = 880
    private static let warningBeepDuration: TimeInterval = 0.15
    private static let warningBeepSpacing: TimeInterval = 0.25
    private static let completeBeepDuration: TimeInterval = warningBeepDuration * 2

    // Keeps strong references to in-flight players so ARC doesn't stop playback
    // partway through — nothing else on the caller side holds one.
    private static var activePlayers: Set<AVAudioPlayer> = []

    /// The "timer's actually done" cue — a single tone, twice as long and played at
    /// full volume so it stands out from the shorter warning beep.
    static func playTimerComplete() {
        play(tone(duration: completeBeepDuration))
    }

    /// A quick triple beep of the same tone at the profile's warning mark (5s or 10s
    /// remaining). `endOnly` never fires here — the "end" cue is always played
    /// separately, by the caller, when the countdown actually reaches zero.
    static func playWarningIfNeeded(remainingSeconds: Int, profile: TimerSoundProfile) {
        switch profile {
        case .endOnly: return
        case .warn5: if remainingSeconds == 5 { playTripleBeep() }
        case .warn10: if remainingSeconds == 10 { playTripleBeep() }
        }
    }

    private static func playTripleBeep() {
        let beep = tone(duration: warningBeepDuration)
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * warningBeepSpacing) {
                play(beep)
            }
        }
    }

    private static func play(_ data: Data) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = 1
        activePlayers.insert(player)
        player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1) {
            activePlayers.remove(player)
        }
    }

    /// Generates a sine-wave beep as in-memory 16-bit PCM WAV data, with a short
    /// fade in/out to avoid a click at the edges.
    private static func tone(duration: TimeInterval) -> Data {
        let frameCount = Int(sampleRate * duration)
        let fadeFrames = max(1, Int(sampleRate * 0.01))

        var pcmData = Data(capacity: frameCount * 2)
        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            var value = Float(sin(2 * .pi * toneFrequency * t))
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
