import AVFoundation
import SwiftUI

/// Every audible cue in one place: the timer beeps, and the spoken announcements.
///
/// Replaces the "Timer sound" picker and the "Announcements" section that used to sit
/// unrelated to each other in `SettingsView`. They were never independent — the beep fired
/// at 5 or 10 seconds while the voice was pinned to a hardcoded 10, so choosing the 5s
/// profile left the two talking over different moments. Each cue now carries its own
/// switch and its own timing.
struct SoundVoiceSettingsView: View {
    @AppStorage("settings.sound.endEnabled") private var soundEndEnabled = true
    @AppStorage("settings.sound.warningEnabled") private var soundWarningEnabled = false
    @AppStorage("settings.sound.warningSeconds") private var soundWarningSeconds = 5

    @AppStorage("settings.speechEnabled") private var speechEnabled = false
    @AppStorage("settings.speechVoiceIdentifier") private var speechVoiceIdentifier = ""
    @AppStorage("settings.voice.announceNextEnabled") private var announceNextEnabled = true
    @AppStorage("settings.voice.announceNextSeconds") private var announceNextSeconds = 10
    @AppStorage("settings.voice.timeLeftEnabled") private var timeLeftEnabled = true
    @AppStorage("settings.voice.countdownEnabled") private var countdownEnabled = false
    @AppStorage("settings.voice.countdownFromSeconds") private var countdownFromSeconds = 3
    @AppStorage("settings.voice.announceStartEnabled") private var announceStartEnabled = true

    var body: some View {
        List {
            soundsSection
            voiceSection
            if speechEnabled {
                announcementsSection
            }
        }
        .fullBleedList()
        // Lowering the announcement mark can strand the countdown above its own range,
        // where the stepper shows a number it can no longer reach. Pulled back down with
        // it, so the two controls always agree about what is possible. On the list rather
        // than on the stepper's row, which doesn't exist while the countdown is off.
        .onChange(of: maxCountdownFrom) { _, newMax in
            if countdownFromSeconds > newMax { countdownFromSeconds = newMax }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(title: "Sounds & Voice")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Owned here rather than by `SettingsView`: pushing this screen fires the parent's
        // `onDisappear`, so leaving the lifecycle up there would tear the synthesizer down
        // underneath this view and leave Preview silent.
        .onAppear {
            SpeechAnnouncer.prepare()
            SpeechAnnouncer.beginVoiceObservation()
        }
        .onDisappear {
            SpeechAnnouncer.teardown()
            SpeechAnnouncer.endVoiceObservation()
        }
        .background(Color.appBackground)
    }

    // MARK: - Sounds

    @ViewBuilder
    private var soundsSection: some View {
        Section {
            Toggle("Sound when the timer ends", isOn: $soundEndEnabled)
                .tint(Color.appAccent)
                .formRow(isLast: false)

            Toggle("Warning sound before the end", isOn: $soundWarningEnabled)
                .tint(Color.appAccent)
                .formRow(isLast: !soundWarningEnabled)

            if soundWarningEnabled {
                Stepper(
                    "Seconds before end: \(soundWarningSeconds)",
                    value: $soundWarningSeconds,
                    in: 1...60
                )
                .formRow()
            }
        } header: {
            FormSectionHeader("Sounds")
        } footer: {
            FormSectionFooter("Applies to every countdown — rest between sets, Follow Along steps, EMOM rounds and AMRAP. The warning is a higher-pitched double beep, so it can't be mistaken for the end.")
        }
    }

    // MARK: - Voice

    @ViewBuilder
    private var voiceSection: some View {
        Section {
            Toggle("Spoken announcements", isOn: $speechEnabled)
                .tint(Color.appAccent)
                .formRow(isLast: !speechEnabled)

            if speechEnabled {
                Picker("Voice", selection: $speechVoiceIdentifier) {
                    ForEach(SpeechAnnouncer.selectableVoices, id: \.identifier) { voice in
                        Text(SpeechAnnouncer.displayName(voice)).tag(voice.identifier)
                    }
                }
                // Explicit, not `.automatic`: in a plain List that resolves to one row per
                // installed voice — dozens of them.
                .pickerStyle(.navigationLink)
                // Stored as "" until something is picked, which matches no tag and leaves
                // the row blank — show the voice that will actually be used.
                .onAppear {
                    if speechVoiceIdentifier.isEmpty,
                       let resolved = SpeechAnnouncer.selectedVoice {
                        speechVoiceIdentifier = resolved.identifier
                    }
                }
                .formRow(isLast: false)

                Button("Preview") { SpeechAnnouncer.preview() }
                    .foregroundStyle(Color.appAccent)
                    .formRow(isLast: false)

                voiceQualityGuidance
            }
        } header: {
            FormSectionHeader("Voice")
        } footer: {
            FormSectionFooter("Spoken cues during a Follow Along workout. Preview plays whatever is switched on below.")
        }
    }

    /// The three announcement cues, each independently switchable. Only shown once the
    /// voice itself is on — controls that can't make a sound invite fiddling with settings
    /// that do nothing.
    @ViewBuilder
    private var announcementsSection: some View {
        Section {
            Toggle("Announce the next exercise", isOn: $announceNextEnabled)
                .tint(Color.appAccent)
                .formRow(isLast: false)

            if announceNextEnabled {
                Stepper(
                    "Seconds before end: \(announceNextSeconds)",
                    value: $announceNextSeconds,
                    in: 3...60
                )
                .formRow(isLast: false)

                Toggle("Notify time left", isOn: $timeLeftEnabled)
                    .tint(Color.appAccent)
                    .formRow(isLast: false)
            }

            Toggle("Count down the last seconds", isOn: $countdownEnabled)
                .tint(Color.appAccent)
                .formRow(isLast: !countdownEnabled)

            if countdownEnabled {
                Stepper(
                    "Count from: \(countdownFromSeconds)",
                    value: $countdownFromSeconds,
                    in: 1...maxCountdownFrom
                )
                .formRow(isLast: false)
            }

            Toggle("Announce each exercise as it starts", isOn: $announceStartEnabled)
                .tint(Color.appAccent)
                .formRow()
        } header: {
            FormSectionHeader("Announcements")
        } footer: {
            FormSectionFooter("When the next exercise is the same one in a different execution type, only the type is spoken — repeating the name would say nothing new.")
        }
    }

    /// Kept strictly below the announcement mark so the two cues can't land on the same
    /// second, where the countdown's first number would cut the announcement off mid-word.
    private var maxCountdownFrom: Int {
        guard announceNextEnabled else { return 10 }
        return max(1, announceNextSeconds - 1)
    }

    /// Always shown, because the good voices are a download away and nothing in the app
    /// can fetch them — highlighted when the device has only the robotic built-ins, so an
    /// unexpectedly poor voice explains itself instead of looking like a bug.
    @ViewBuilder
    private var voiceQualityGuidance: some View {
        let needsDownload = SpeechAnnouncer.hasOnlyDefaultVoices

        VStack(alignment: .leading, spacing: 8) {
            if needsDownload {
                Label("No natural voice installed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appRust)
            }

            Text(needsDownload
                 ? "Only the basic built-in voice is available, which sounds robotic. For a natural voice, download an Enhanced or Premium one:"
                 : "More natural voices can be downloaded any time:")
                .font(.footnote)
                .foregroundStyle(Color.appInkMuted)

            Text("Settings › Accessibility › Spoken Content › Voices › English")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appInk)

            // iOS only lets an app open its own Settings page; the path above covers the
            // rest of the journey. A private deep link into Accessibility would risk App
            // Store rejection and break between releases.
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundStyle(Color.appAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formRowPadding()
        // The tint goes on the content, not via `listRowBackground` — `fullBleedRow` sets
        // that to clear and paints the surface itself.
        .background(needsDownload ? Color.appRust.opacity(0.08) : Color.clear)
        .fullBleedRow()
    }
}
