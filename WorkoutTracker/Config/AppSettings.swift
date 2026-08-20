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
}
