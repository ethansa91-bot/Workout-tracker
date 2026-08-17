import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("settings.defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("settings.weightUnit") private var weightUnit = "lb"
    @AppStorage("settings.timerSoundProfile") private var timerSoundProfile = TimerSoundProfile.endOnly

    @Environment(\.modelContext) private var context
    @State private var showingResetConfirm = false
    @State private var resetErrorMessage: String?
    @State private var testDataMessage: String?

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

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Delete All Data & Reinitialize", systemImage: "trash")
                            .foregroundStyle(Color.appDanger)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently deletes every workout, session, custom exercise, and note on this device, then reloads the starter exercise catalog from scratch. This cannot be undone.")
                }

                Section {
                    Button("Generate Test Workouts") {
                        generateTestWorkouts()
                    }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Creates one workout per section type (Rep, Time, EMOM, AMRAP), each with the same 5 exercises chosen to cover every exercise-media state — picture only, video only, both, and neither — so they're quick to spot-check. Re-running replaces the previous set.")
                }
            }
            .themedListBackground()
            .navigationTitle("Settings")
            .alert(
                "Delete all data?",
                isPresented: $showingResetConfirm
            ) {
                Button("Delete Everything", role: .destructive) { performReset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes every workout, session, custom exercise, and note on this device, then reloads the starter exercise catalog. This cannot be undone.")
            }
            .alert("Reset Failed", isPresented: Binding(
                get: { resetErrorMessage != nil },
                set: { if !$0 { resetErrorMessage = nil } }
            )) {
                Button("OK") { resetErrorMessage = nil }
            } message: {
                Text(resetErrorMessage ?? "")
            }
            .alert("Test Workouts", isPresented: Binding(
                get: { testDataMessage != nil },
                set: { if !$0 { testDataMessage = nil } }
            )) {
                Button("OK") { testDataMessage = nil }
            } message: {
                Text(testDataMessage ?? "")
            }
        }
    }

    private func performReset() {
        do {
            try DataResetService.resetAndReseed(context: context)
        } catch {
            resetErrorMessage = error.localizedDescription
        }
    }

    private func generateTestWorkouts() {
        do {
            try TestDataService.generateTestWorkouts(context: context)
            testDataMessage = "Created \"Test — Rep\", \"Test — Time\", \"Test — EMOM\", and \"Test — AMRAP\"."
        } catch {
            testDataMessage = "Failed: \(error.localizedDescription)"
        }
    }
}
