import SwiftUI

struct SettingsView: View {
    @AppStorage("settings.defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("settings.weightUnit") private var weightUnit = "lb"
    @AppStorage("settings.timerSoundProfile") private var timerSoundProfile = TimerSoundProfile.endOnly

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout defaults") {
                    Stepper("Default rest: \(defaultRestSeconds)s", value: $defaultRestSeconds, in: 15...300, step: 15)
                }
                Section("Units") {
                    Picker("Weight unit", selection: $weightUnit) {
                        Text("kg").tag("kg")
                        Text("lb").tag("lb")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Timer sound") {
                    Picker("Timer sound", selection: $timerSoundProfile) {
                        ForEach(TimerSoundProfile.allCases) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                SyncStatusView()
            }
            .themedListBackground()
            .navigationTitle("Settings")
        }
    }
}
