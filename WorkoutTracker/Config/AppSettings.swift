import AVFoundation
import Foundation

/// Scalar device preferences — not modeled in SwiftData since they don't need
/// relational modeling or sync tombstone tracking.
enum AppSettings {
    private static let defaultRestSecondsKey = "settings.defaultRestSeconds"
    private static let weightUnitKey = "settings.weightUnit"
    /// Superseded by the `sound.*` keys below. Still read once, by
    /// `SoundSettingsMigration`, so an upgrading device keeps the cues it had.
    static let legacyTimerSoundProfileKey = "settings.timerSoundProfile"
    private static let soundEndEnabledKey = "settings.sound.endEnabled"
    private static let soundWarningEnabledKey = "settings.sound.warningEnabled"
    private static let soundWarningSecondsKey = "settings.sound.warningSeconds"
    private static let speechEnabledKey = "settings.speechEnabled"
    private static let speechVoiceIdentifierKey = "settings.speechVoiceIdentifier"
    private static let shareCodeKey = "settings.shareCode"
    private static let displayNameKey = "settings.displayName"
    private static let workoutVideoAutoplayKey = "settings.workoutVideoAutoplay"
    private static let voiceAnnounceNextEnabledKey = "settings.voice.announceNextEnabled"
    private static let voiceAnnounceNextSecondsKey = "settings.voice.announceNextSeconds"
    private static let voiceTimeLeftEnabledKey = "settings.voice.timeLeftEnabled"
    private static let voiceCountdownEnabledKey = "settings.voice.countdownEnabled"
    private static let voiceCountdownFromSecondsKey = "settings.voice.countdownFromSeconds"
    private static let voiceAnnounceStartEnabledKey = "settings.voice.announceStartEnabled"

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

    // MARK: - Timer sounds
    //
    // Three independent settings where there used to be one three-case profile. The end
    // tone was previously unconditional and the warning could only fire at 5s or 10s;
    // both are now free, which is what lets the beep and the spoken cue below be timed
    // against each other rather than one being hardcoded.

    /// Defaults to on — the end tone was unconditional before this setting existed, and
    /// a timer that finishes in silence would be a surprising upgrade.
    static var soundEndEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: soundEndEnabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: soundEndEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: soundEndEnabledKey) }
    }

    /// Off by default, matching the old `.endOnly` profile.
    static var soundWarningEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: soundWarningEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: soundWarningEnabledKey) }
    }

    static var soundWarningSeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: soundWarningSecondsKey)
            return stored == 0 ? 5 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: soundWarningSecondsKey) }
    }

    /// Whether a Follow Along step autoplays the exercise's video.
    ///
    /// On unless turned off — the video is the point of a Follow Along step. It is a real
    /// battery cost though (a web view, video decode, and network per exercise, on a
    /// screen held awake for the whole workout), so it's worth being able to drop back to
    /// the still. Defaults to `true` via an explicit presence check, since
    /// `UserDefaults.bool` reports `false` for a key that was never written.
    static var workoutVideoAutoplayEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: workoutVideoAutoplayKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: workoutVideoAutoplayKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: workoutVideoAutoplayKey) }
    }

    // MARK: - Spoken announcements

    /// Off until asked for — a workout that starts talking unprompted is worse than
    /// one that stays quiet, and `SpeechAnnouncer` never touches the audio session
    /// while this is false.
    static var speechEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: speechEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: speechEnabledKey) }
    }

    /// Say what's coming next, so many seconds before the current step ends. On by
    /// default — it was the only spoken cue before this, and turning speech on at all is
    /// already an explicit choice.
    static var voiceAnnounceNextEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: voiceAnnounceNextEnabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: voiceAnnounceNextEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceAnnounceNextEnabledKey) }
    }

    static var voiceAnnounceNextSeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: voiceAnnounceNextSecondsKey)
            return stored == 0 ? 10 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceAnnounceNextSecondsKey) }
    }

    /// Append "Ten seconds left" to the announcement above — the second half of the one
    /// combined cue this used to be, now separable from it.
    static var voiceTimeLeftEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: voiceTimeLeftEnabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: voiceTimeLeftEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceTimeLeftEnabledKey) }
    }

    /// Speak the last few seconds one at a time — "three, two, one". Independent of the
    /// announcement, and off by default: it is new behaviour, not a restatement of
    /// anything the app did before.
    static var voiceCountdownEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: voiceCountdownEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: voiceCountdownEnabledKey) }
    }

    static var voiceCountdownFromSeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: voiceCountdownFromSecondsKey)
            return stored == 0 ? 3 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceCountdownFromSecondsKey) }
    }

    /// Name each step as it begins. On by default — this is what "Speak exercise names"
    /// did, so an upgrading device that had speech on keeps hearing it.
    static var voiceAnnounceStartEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: voiceAnnounceStartEnabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: voiceAnnounceStartEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: voiceAnnounceStartEnabledKey) }
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

    /// A **cache** of the name this user publishes to the people who follow them, for
    /// the same reason and with the same caveat as `shareCode`: the public `Profile`
    /// record is the source of truth, and this only exists so the UI can render a name
    /// before the network answers. Empty (not nil) once the user has cleared it.
    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: displayNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: displayNameKey) }
    }

    /// Whether this user has ever chosen a name. Drives the one-time prompt shown when
    /// following someone — the point of the name is that the other side sees a person
    /// rather than `ACDE-3F7K`, which only works if it's set before the follow lands.
    static var hasDisplayName: Bool {
        !(displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
