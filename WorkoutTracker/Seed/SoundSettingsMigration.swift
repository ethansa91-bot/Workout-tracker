import Foundation

/// Translates the retired `settings.timerSoundProfile` into the three independent sound
/// settings that replaced it, once.
///
/// Without this an upgrading device silently falls back to the new defaults — end tone
/// on, warning off — which would quietly drop the warning beep for anyone who had chosen
/// `warn5` or `warn10`. The new defaults are correct for a fresh install and wrong for
/// every device that already answered this question.
///
/// Not a `SwiftData` migration: these are `UserDefaults` scalars, so there is no store to
/// touch and no context to pass.
enum SoundSettingsMigration {
    private static let migratedFlagKey = "migration.soundSettingsV1"

    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedFlagKey) }

        // Never chosen — the new defaults already say what this device wants, and writing
        // them explicitly would only freeze today's values against a later change.
        guard let profile = UserDefaults.standard.string(forKey: AppSettings.legacyTimerSoundProfileKey) else { return }

        // The end tone was unconditional under every one of the old profiles, so it is on
        // in all three branches — the profile only ever chose the warning.
        AppSettings.soundEndEnabled = true
        switch profile {
        case "warn5":
            AppSettings.soundWarningEnabled = true
            AppSettings.soundWarningSeconds = 5
        case "warn10":
            AppSettings.soundWarningEnabled = true
            AppSettings.soundWarningSeconds = 10
        default:
            // "endOnly", and anything unrecognized — the old default.
            AppSettings.soundWarningEnabled = false
        }
    }
}
