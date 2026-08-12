import Foundation

/// Scalar device preferences — not modeled in SwiftData since they don't need
/// relational modeling or sync tombstone tracking.
enum AppSettings {
    private static let defaultRestSecondsKey = "settings.defaultRestSeconds"
    private static let weightUnitKey = "settings.weightUnit"
    private static let timerSoundProfileKey = "settings.timerSoundProfile"

    static var defaultRestSeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultRestSecondsKey)
            return stored == 0 ? 90 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultRestSecondsKey) }
    }

    static var weightUnit: String {
        get { UserDefaults.standard.string(forKey: weightUnitKey) ?? "lb" }
        set { UserDefaults.standard.set(newValue, forKey: weightUnitKey) }
    }

    static var timerSoundProfile: TimerSoundProfile {
        get {
            UserDefaults.standard.string(forKey: timerSoundProfileKey).flatMap(TimerSoundProfile.init) ?? .endOnly
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: timerSoundProfileKey) }
    }
}
