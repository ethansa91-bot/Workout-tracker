import AVFoundation
import UIKit

/// Holds the `AVSpeechSynthesizer` and reports back when an utterance stops.
///
/// A locally-scoped synthesizer is deallocated as soon as the calling function returns,
/// which cuts the utterance off mid-word — so one has to be held somewhere. It used to be
/// held in a `static let`, which meant it was created on first use and then lived for the
/// rest of the process; `SpeechAnnouncer` now owns one of these only while something can
/// actually speak.
///
/// The delegate callbacks are what balance `AudioSessionController`'s refcount for speech:
/// every utterance ends in exactly one of `didFinish` or `didCancel`.
@MainActor
private final class SpeechEngine: NSObject, AVSpeechSynthesizerDelegate {
    let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // `nonisolated` with an explicit hop: AVFoundation makes no promise about which queue
    // delivers these.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in AudioSessionController.endActivity() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in AudioSessionController.endActivity() }
    }
}

/// Spoken cues during a Follow Along section — the exercise name as each step starts,
/// and a combined warning near the end of the current step.
///
/// Nothing can speak until `prepare()` has been called, and `teardown()` puts it back to
/// that state. Only two places call `prepare()`: the Follow Along runner and the Settings
/// preview. That makes "speech exists during a workout, and nowhere else" an invariant the
/// type enforces rather than a convention the call sites happen to follow.
@MainActor
enum SpeechAnnouncer {
    private static var engine: SpeechEngine?

    private static var cachedLanguagePool: [AVSpeechSynthesisVoice]?
    private static var voiceCacheObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    /// Creates the synthesizer and warms the audio session, so the first cue doesn't pay
    /// for either inline and lose its opening syllable. Idempotent.
    static func prepare() {
        AudioSessionController.prewarm()
        guard engine == nil else { return }
        engine = SpeechEngine()
    }

    /// Stops anything in flight, releases the synthesizer, and drops the audio session.
    /// After this, `speak` and `preview` do nothing until `prepare()` is called again.
    static func teardown() {
        engine?.synthesizer.stopSpeaking(at: .immediate)
        engine = nil
        // Unconditional rather than leaning on the delegate's `didCancel`: if an utterance
        // never reported back, the refcount would be stuck above zero and the session
        // would stay active for the rest of the process — the exact leak this replaced.
        AudioSessionController.deactivateNow()
    }

    // MARK: - Voice list

    /// Voices for the device's language, falling back to English when it has none.
    ///
    /// Cached, because `AVSpeechSynthesisVoice.speechVoices()` enumerates every installed
    /// voice — well over a hundred on a device with downloads — and Settings reads through
    /// here up to three times per body pass, via `selectableVoices` and
    /// `hasOnlyDefaultVoices`. Settings stays mounted once visited, so that repeated on
    /// every unrelated change.
    private static var languagePool: [AVSpeechSynthesisVoice] {
        if let cachedLanguagePool { return cachedLanguagePool }
        let prefix = String(Locale.current.identifier.prefix(2)).lowercased()
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matching = all.filter { $0.language.lowercased().hasPrefix(prefix) }
        let pool = matching.isEmpty ? all.filter { $0.language.lowercased().hasPrefix("en") } : matching
        cachedLanguagePool = pool
        return pool
    }

    /// Drops the voice cache whenever the app comes back to the foreground.
    ///
    /// Not a process-lifetime cache: `voiceQualityGuidance` sends the user to iOS Settings
    /// to download a better voice, and they come straight back expecting the picker to
    /// show it. Installing one can only happen while this app is backgrounded, so
    /// returning to the foreground is exactly when the set can have changed.
    ///
    /// Scoped to the Settings screen — it exists only to keep that picker honest, and
    /// registering it forever from a getter left an observer alive for the whole process.
    static func beginVoiceObservation() {
        guard voiceCacheObserver == nil else { return }
        voiceCacheObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { cachedLanguagePool = nil }
        }
    }

    static func endVoiceObservation() {
        guard let voiceCacheObserver else { return }
        NotificationCenter.default.removeObserver(voiceCacheObserver)
        self.voiceCacheObserver = nil
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

    /// `voice.name` with a quality suffix removed if iOS already put one there.
    ///
    /// A downloaded voice arrives named `"Ava (Enhanced)"`, so appending the quality
    /// unconditionally produced `"Ava (Enhanced) (Enhanced)"`. Only a trailing
    /// parenthetical whose contents are one of the three quality words is stripped — a
    /// voice legitimately named with a parenthetical (a regional variant, say) keeps it.
    private static func baseName(_ voice: AVSpeechSynthesisVoice) -> String {
        let name = voice.name
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return name }
        let inner = name[name.index(after: open)..<name.index(before: name.endIndex)]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard ["premium", "enhanced", "default"].contains(inner) else { return name }
        return String(name[..<open]).trimmingCharacters(in: .whitespaces)
    }

    /// `"Ava (Premium)"` — the name alone isn't enough to tell a downloaded natural
    /// voice from the robotic built-in of the same name.
    static func displayName(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(baseName(voice)) (\(qualityLabel(voice)))"
    }

    /// Every downloaded Enhanced/Premium voice, best first. These are the ones worth
    /// listening to; iOS fetches them on demand, so this is empty on a device that
    /// has never downloaded any.
    static var naturalVoices: [AVSpeechSynthesisVoice] {
        languagePool
            .filter { rank($0.quality) > 1 }
            .sorted {
                // Sorted on the stripped name, or `"Ava (Enhanced)"` would order under
                // the suffix rather than alphabetically with the other A voices.
                rank($0.quality) != rank($1.quality)
                    ? rank($0.quality) > rank($1.quality)
                    : baseName($0) < baseName($1)
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

    // MARK: - Speaking

    /// Speaks `text`, interrupting anything still in flight — a stale "ten seconds
    /// left" finishing over the next step's name would be worse than cutting it off.
    static func speak(_ text: String) {
        guard AppSettings.speechEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        utter(text)
    }

    /// Ignores the enabled flag so the Settings preview works before you turn it on.
    static func preview() {
        utter("Ten seconds left. Next: Push Up")
    }

    private static func utter(_ text: String) {
        // No engine means nothing has called `prepare()` — i.e. we're not in a Follow
        // Along section and not on the Settings screen. Staying silent is the point.
        guard let engine else { return }

        // Claimed before the interrupt so the count can't dip to zero between the two and
        // deactivate the session out from under the utterance we're about to start. The
        // cancelled one balances itself through `didCancel`.
        AudioSessionController.beginActivity()
        if engine.synthesizer.isSpeaking {
            engine.synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        engine.synthesizer.speak(utterance)
    }

    static func stop() {
        guard let engine, engine.synthesizer.isSpeaking else { return }
        // `didCancel` releases the audio session claim.
        engine.synthesizer.stopSpeaking(at: .immediate)
    }
}
