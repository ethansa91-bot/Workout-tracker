import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("settings.defaultRestSeconds") private var defaultRestSeconds = 90
    @AppStorage("settings.weightUnit") private var weightUnit = "lb"
    /// Read-only here — the Sounds & Voice screen owns every audio setting. Kept so the
    /// row can say whether the voice is on without pushing into it.
    @AppStorage("settings.speechEnabled") private var speechEnabled = false
    @AppStorage("settings.workoutVideoAutoplay") private var workoutVideoAutoplay = true

    @Environment(\.modelContext) private var context
    @State private var showingResetConfirm = false
    @State private var resetErrorMessage: String?
    @State private var testDataMessage: String?
    @State private var importMessage: String?
    @State private var showingExportPicker = false
    @State private var showingArchiveExport = false
    @State private var showingArchiveImporter = false
    /// Held between picking a file and confirming: the archive is decoded and validated
    /// up front so the confirmation can say what's actually in it, and so a broken file
    /// fails before anything is written.
    @State private var pendingArchive: ArchivePayload?
    @State private var archiveMessage: String?

    @Query private var followedUsers: [FollowedUser]
    private var followedCount: Int { followedUsers.filter { $0.deletedAt == nil }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            PageTitleBand(title: "Settings", reservesButtonRow: true)

            List {
                Section {
                    Stepper("Default rest: \(defaultRestSeconds)s", value: $defaultRestSeconds, in: 15...300, step: 15)
                        .settingsRow()
                } header: {
                    sectionHeader("Workout defaults")
                }

                Section {
                    Picker("Weight unit", selection: $weightUnit) {
                        Text("kg").tag("kg")
                        Text("lb").tag("lb")
                    }
                    .pickerStyle(.segmented)
                    .settingsRow()
                } header: {
                    sectionHeader("Units")
                }

                Section {
                    NavigationLink {
                        SoundVoiceSettingsView()
                    } label: {
                        HStack {
                            Text("Sounds & Voice")
                            Spacer()
                            Text(speechEnabled ? "Sounds, voice on" : "Sounds only")
                                .foregroundStyle(.secondary)
                        }
                        .settingsRowPadding()
                    }
                    .fullBleedRow()
                } header: {
                    sectionHeader("Sounds & Voice")
                } footer: {
                    sectionFooter("Timer beeps and spoken announcements, each with its own switch and timing.")
                }

                Section {
                    Toggle("Autoplay exercise video", isOn: $workoutVideoAutoplay)
                        .tint(Color.appAccent)
                        .settingsRow()
                } header: {
                    sectionHeader("Exercise video")
                } footer: {
                    sectionFooter("Plays the exercise's video automatically during a Follow Along step. Turning this off shows a tappable still instead, which uses noticeably less battery and data over a long workout.")
                }

                Section {
                    NavigationLink {
                        SyncDiagnosticsView()
                    } label: {
                        HStack {
                            Text("iCloud Sync")
                            Spacer()
                            Text(ContainerStatus.isCloudEnabled ? "On" : "Off")
                                .foregroundStyle(.secondary)
                        }
                        .settingsRowPadding()
                    }
                    .fullBleedRow()
                } header: {
                    sectionHeader("Sync")
                } footer: {
                    sectionFooter("Workouts sync automatically across devices signed into the same Apple Account — there's no separate login. Open this to check sync status.")
                }

                Section {
                    NavigationLink {
                        SharingHomeView()
                    } label: {
                        HStack {
                            Text("Share Workouts")
                            Spacer()
                            Text(followedCount == 0 ? "Off" : "\(followedCount) following")
                                .foregroundStyle(.secondary)
                        }
                        .settingsRowPadding()
                    }
                    .fullBleedRow()
                } header: {
                    sectionHeader("Sharing")
                } footer: {
                    sectionFooter("Share a code with someone and they can save the workouts you publish — and you can save theirs. Nothing is shared until you publish it, and only people with your code can see it.")
                }

                Section {
                    Button("Export Full Archive") {
                        showingArchiveExport = true
                    }
                    .settingsRow(isLast: false)
                    Button("Import Full Archive") {
                        showingArchiveImporter = true
                    }
                    .settingsRow()
                } header: {
                    sectionHeader("Backup")
                } footer: {
                    sectionFooter("A single .zip with everything: your catalog, workouts, templates, personal records, generated exercise pictures, and optionally your session history. Importing merges by matching entries — re-importing the same archive changes nothing.")
                }

                Section {
                    Button("Export Workouts") {
                        showingExportPicker = true
                    }
                    .settingsRow()
                } header: {
                    sectionHeader("Export")
                } footer: {
                    sectionFooter("Choose which workouts to include, then save a JSON file. Section templates are always included. The file uses the same format as the app's bundled starter workouts.")
                }

                Section {
                    Button("Import Workouts") {
                        importWorkouts()
                    }
                    .settingsRow()
                } header: {
                    sectionHeader("Import")
                } footer: {
                    sectionFooter("Adds the starter workouts bundled with the app. Every tap adds another fresh copy, so importing twice gives you duplicates. If an exercise in the file isn't in your catalog, nothing is imported and you'll see which ones are missing.")
                }

                Section {
                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Label("Delete All Data & Reinitialize", systemImage: "trash")
                            .foregroundStyle(Color.appDanger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .settingsRowPadding()
                            // Grouped style used to contain this in its own card; the
                            // tint is what keeps it reading as set apart now that every
                            // row is one continuous white band.
                            .background(Color.appDanger.opacity(0.06))
                    }
                    .fullBleedRow()
                } header: {
                    sectionHeader("Danger Zone")
                } footer: {
                    sectionFooter("Permanently deletes every workout, session, custom exercise, and note on this device, then reloads the starter exercise catalog from scratch. This cannot be undone.")
                }

                Section {
                    Button("Generate Test Workouts") {
                        generateTestWorkouts()
                    }
                    .settingsRow()
                } header: {
                    sectionHeader("Testing")
                } footer: {
                    sectionFooter("Creates one workout per section type (Rep, Time, EMOM, AMRAP), each with the same 5 exercises chosen to cover every exercise-media state — picture only, video only, both, and neither — so they're quick to spot-check. Re-running replaces the previous set.")
                }
            }
            .fullBleedList()
            }
            // No speech lifecycle here any more — `SoundVoiceSettingsView` owns it. A
            // push fires this view's `onDisappear`, so keeping it would have torn the
            // synthesizer down underneath the screen that needs it.
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingExportPicker) {
                WorkoutExportPickerSheet()
            }
            .sheet(isPresented: $showingArchiveExport) {
                ArchiveExportSheet()
            }
            .fileImporter(
                isPresented: $showingArchiveImporter,
                allowedContentTypes: [.zip]
            ) { result in
                handleArchiveSelection(result)
            }
            .alert("Import this archive?", isPresented: Binding(
                get: { pendingArchive != nil },
                set: { if !$0 { pendingArchive = nil } }
            )) {
                Button("Import") { performArchiveImport() }
                Button("Cancel", role: .cancel) { pendingArchive = nil }
            } message: {
                Text(archiveConfirmationMessage)
            }
            .alert("Archive", isPresented: Binding(
                get: { archiveMessage != nil },
                set: { if !$0 { archiveMessage = nil } }
            )) {
                Button("OK") { archiveMessage = nil }
            } message: {
                Text(archiveMessage ?? "")
            }
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
            .alert("Import Workouts", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    // MARK: - Row styling

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.appInkMuted)
            // Stock headers uppercase their text.
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
            .listRowInsets(EdgeInsets())
            // Sits on the cream ground rather than on a white band, the way a grouped
            // header did.
            .listRowBackground(Color.clear)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.appInkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    private func performReset() {
        do {
            try DataResetService.resetAndReseed(context: context)
        } catch {
            resetErrorMessage = error.localizedDescription
        }
    }

    private func importWorkouts() {
        do {
            let summary = try WorkoutImportService.importBundledWorkouts(context: context)
            importMessage = "Imported \(summary.workouts) workouts, \(summary.sections) sections, \(summary.timeSteps) time steps, and \(summary.repExercises) rep exercises."
        } catch {
            importMessage = error.localizedDescription
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

    /// Decode and validate on selection, not on confirm — a malformed archive should be
    /// rejected before the user is asked to commit to it, and the confirmation needs the
    /// contents to describe them.
    private func handleArchiveSelection(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            archiveMessage = error.localizedDescription
        case .success(let url):
            do {
                pendingArchive = try ArchiveImportService.inspect(url: url)
            } catch {
                archiveMessage = error.localizedDescription
            }
        }
    }

    private var archiveConfirmationMessage: String {
        guard let payload = pendingArchive else { return "" }
        var lines: [String] = []
        let date = payload.manifest.exportedAt.formatted(date: .abbreviated, time: .shortened)
        lines.append("Exported \(date).")

        let counts = payload.manifest.counts
        var parts: [String] = []
        if let value = counts["exercises"], value > 0 { parts.append("\(value) exercises") }
        if let value = counts["workouts"], value > 0 { parts.append("\(value) workouts") }
        if let value = counts["sessions"], value > 0 { parts.append("\(value) sessions") }
        if let value = counts["images"], value > 0 { parts.append("\(value) pictures") }
        if !parts.isEmpty {
            lines.append("Contains \(parts.joined(separator: ", ")).")
        }

        lines.append("Entries already on this device are updated only when the archive's copy is newer. Nothing is deleted.")

        // Worth stating plainly: `Workout.isLocked` is computed from session presence,
        // so restoring history permanently blocks editing those workouts.
        if payload.manifest.includesSessionHistory, (counts["sessions"] ?? 0) > 0 {
            lines.append("Because this includes session history, any workout it references becomes locked for editing — clone it to make changes.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func performArchiveImport() {
        guard let payload = pendingArchive else { return }
        pendingArchive = nil
        do {
            let summary = try ArchiveImportService.apply(payload, context: context)
            var parts = ["Added \(summary.totalInserted).", "Updated \(summary.totalUpdated)."]
            if summary.totalSkipped > 0 {
                parts.append("Left \(summary.totalSkipped) unchanged — this device's copy was already current.")
            }
            if summary.imagesRestored > 0 {
                parts.append("Restored \(summary.imagesRestored) picture\(summary.imagesRestored == 1 ? "" : "s").")
            }
            archiveMessage = parts.joined(separator: " ")
        } catch {
            archiveMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

private extension View {
    /// The horizontal gutter a settings control needs now that row insets are zeroed —
    /// without it a Stepper's ± or a segmented control sits flush against the screen.
    func settingsRowPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    /// A settings control as a full-bleed row: its own gutter, then the shared band.
    func settingsRow(isLast: Bool = true) -> some View {
        settingsRowPadding()
            .fullBleedRow(isLast: isLast)
    }
}
