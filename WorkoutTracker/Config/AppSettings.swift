import AVFoundation
import Foundation

/// Scalar device preferences — not modeled in SwiftData since they don't need
/// relational modeling or sync tombstone tracking.
enum AppSettings {
    private static let defaultRestSecondsKey = "settings.defaultRestSeconds"
    private static let weightUnitKey = "settings.weightUnit"
    private static let timerSoundProfileKey = "settings.timerSoundProfile"
    private static let speechEnabledKey = "settings.speechEnabled"
    private static let speechVoiceIdentifierKey = "settings.speechVoiceIdentifier"
    private static let shareCodeKey = "settings.shareCode"

    static var defaultRestSeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultRestSecondsKey)
            return stored == 0 ? 90 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultRestSecondsKey) }
    }

    /// Defaults to kg. Note this is only the fallback for a device that has never
    /// chosen — `WeightUnitKgMigration` handles devices that already stored "lb".
    /// Logged sets snapshot their own unit, so changing this never reinterprets history.
    static var weightUnit: String {
        get { UserDefaults.standard.string(forKey: weightUnitKey) ?? "kg" }
        set { UserDefaults.standard.set(newValue, forKey: weightUnitKey) }
    }

    static var timerSoundProfile: TimerSoundProfile {
        get {
            UserDefaults.standard.string(forKey: timerSoundProfileKey).flatMap(TimerSoundProfile.init) ?? .endOnly
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: timerSoundProfileKey) }
    }

    // MARK: - Spoken announcements

    /// Off until asked for — a workout that starts talking unprompted is worse than
    /// one that stays quiet, and `SpeechAnnouncer` never touches the audio session
    /// while this is false.
    static var speechEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: speechEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: speechEnabledKey) }
    }

    /// `nil` means "whatever the device offers first" — resolved by
    /// `SpeechAnnouncer.selectedVoice` rather than being stamped here, so the setting
    /// keeps working if the chosen voice is later removed from the device.
    static var speechVoiceIdentifier: String? {
        get { UserDefaults.standard.string(forKey: speechVoiceIdentifierKey) }
        set { UserDefaults.standard.set(newValue, forKey: speechVoiceIdentifierKey) }
    }

    /// A **cache** of this device's share code, not the source of truth — that lives in
    /// the user's public `Profile` record. `UserDefaults` never syncs between a user's
    /// own devices, so treating it as authoritative would let two devices mint two
    /// different codes for one person. Kept only so the UI has something to render
    /// before the network answers.
    static var shareCode: String? {
        get { UserDefaults.standard.string(forKey: shareCodeKey) }
        set { UserDefaults.standard.set(newValue, forKey: shareCodeKey) }
    }
}
