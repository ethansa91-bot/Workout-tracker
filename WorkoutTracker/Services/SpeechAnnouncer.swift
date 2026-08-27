import AVFoundation

/// Spoken cues during a Follow Along section — the exercise name as each step starts,
/// and a combined warning near the end of the current step.
///
/// The synthesizer is held statically for the same reason `SoundPlayer` keeps its
/// players in a set: a locally-scoped `AVSpeechSynthesizer` is deallocated as soon as
/// the calling function returns, which cuts the utterance off mid-word.
@MainActor
enum SpeechAnnouncer {
    private static let synthesizer = AVSpeechSynthesizer()

    /// Voices for the device's language, falling back to English when it has none.
    private static var languagePool: [AVSpeechSynthesisVoice] {
        let prefix = String(Locale.current.identifier.prefix(2)).lowercased()
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matching = all.filter { $0.language.lowercased().hasPrefix(prefix) }
        return matching.isEmpty ? all.filter { $0.language.lowercased().hasPrefix("en") } : matching
    }

    private static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    /// `"Ava (Premium)"` — the name alone isn't enough to tell a downloaded natural
    /// voice from the robotic built-in of the same name.
    static func displayName(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) (\(qualityLabel(voice)))"
    }

    /// Every downloaded Enhanced/Premium voice, best first. These are the ones worth
    /// listening to; iOS fetches them on demand, so this is empty on a device that
    /// has never downloaded any.
    static var naturalVoices: [AVSpeechSynthesisVoice] {
        languagePool
            .filter { rank($0.quality) > 1 }
            .sorted {
                rank($0.quality) != rank($1.quality)
                    ? rank($0.quality) > rank($1.quality)
                    : $0.name < $1.name
            }
    }

    /// True when the device has nothing better than the built-in robotic voices, so
    /// Settings can say so rather than silently offering a poor one.
    static var hasOnlyDefaultVoices: Bool { naturalVoices.isEmpty }

    /// What the picker offers: every natural voice, or — when none are installed —
    /// the single best of what's left, so speech still works while the UI explains
    /// how to get something better.
    static var selectableVoices: [AVSpeechSynthesisVoice] {
        if !naturalVoices.isEmpty { return naturalVoices }
        if let best = languagePool.max(by: { rank($0.quality) < rank($1.quality) }) {
            return [best]
        }
        return []
    }

    /// The stored voice, or the best available when nothing is stored or the chosen
    /// voice has since been removed from the device.
    static var selectedVoice: AVSpeechSynthesisVoice? {
        if let id = AppSettings.speechVoiceIdentifier, !id.isEmpty,
           let match = selectableVoices.first(where: { $0.identifier == id }) {
            return match
        }
        return selectableVoices.first
    }

    /// Speaks `text`, interrupting anything still in flight — a stale "ten seconds
    /// left" finishing over the next step's name would be worse than cutting it off.
    static func speak(_ text: String) {
        guard AppSettings.speechEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        activateSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        synthesizer.speak(utterance)
    }

    /// Ignores the enabled flag so the Settings preview works before you turn it on.
    static func preview() {
        activateSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: "Ten seconds left. Next: Push Up")
        utterance.voice = selectedVoice
        synthesizer.speak(utterance)
    }

    static func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// `.duckOthers` alongside `.mixWithOthers` so background music dips under the cue
    /// instead of stopping, and the timer beeps still play over the top.
    private static func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }
}
