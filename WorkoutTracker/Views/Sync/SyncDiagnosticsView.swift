import SwiftUI
import SwiftData
import CloudKit

/// Read-only reporting on what iCloud sync is actually doing.
///
/// Sync has no UI of its own — it either silently works or silently doesn't, and the
/// three failure modes users hit (not signed into iCloud, container fell back to
/// local-only, sync simply still in progress) are indistinguishable without this. None
/// of it changes behavior; it exists so a failure is legible instead of mysterious.
struct SyncDiagnosticsView: View {
    @Environment(\.modelContext) private var context

    @State private var accountStatus: CKAccountStatus?
    @State private var workoutCount: Int?
    @State private var sessionCount: Int?

    private var monitor: CloudKitSyncMonitor { CloudKitSyncMonitor.shared }
    private var reachability: NetworkReachability { NetworkReachability.shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Mode") {
                    Text(ContainerStatus.isCloudEnabled ? "iCloud sync active" : "Local only")
                        .foregroundStyle(ContainerStatus.isCloudEnabled ? Color.primary : Color.appDanger)
                }
                LabeledContent("iCloud account", value: accountStatusText)
                LabeledContent("Network") {
                    Text(reachability.isOnline ? "Online" : "Offline")
                        .foregroundStyle(reachability.isOnline ? Color.primary : Color.appDanger)
                }
            } header: {
                Text("Status")
            } footer: {
                Text(statusFooter)
            }

            if let failure = ContainerStatus.failure {
                Section {
                    Text("\(failure.domain) \(failure.code)")
                        .font(.footnote.monospaced())
                    Text(failure.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Why iCloud is unavailable")
                }
            }

            Section {
                LabeledContent("Last download", value: eventText(monitor.lastImport))
                LabeledContent("Last upload", value: eventText(monitor.lastExport))
                LabeledContent("Last setup", value: eventText(monitor.lastSetup))
            } header: {
                Text("Activity")
            } footer: {
                Text("The first sync after installing can take several minutes. Downloads arrive on their own once the app has been opened at least once on each device.")
            }

            Section {
                LabeledContent("Workouts", value: workoutCount.map(String.init) ?? "—")
                LabeledContent("Sessions", value: sessionCount.map(String.init) ?? "—")
            } header: {
                Text("On this device")
            } footer: {
                Text("Compare these against your other device to see whether a sync has completed.")
            }

            Section {
                Button("Refresh") { refresh() }
            }
        }
        .themedListBackground()
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            refresh()
        }
    }

    private var accountStatusText: String {
        switch accountStatus {
        case .available: return "Signed in"
        case .noAccount: return "Not signed in"
        case .restricted: return "Restricted"
        case .couldNotDetermine: return "Unknown"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        case .none: return "Checking…"
        @unknown default: return "Unknown"
        }
    }

    private var statusFooter: String {
        if !ContainerStatus.isCloudEnabled {
            return "This device is saving data locally only — nothing is being sent to or received from iCloud."
        }
        switch accountStatus {
        case .noAccount:
            return "Sign in to iCloud in Settings, and make sure iCloud Drive is on, to sync across your devices."
        case .restricted:
            return "iCloud is restricted on this device, likely by Screen Time or a device management profile."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable — this usually resolves on its own."
        default:
            return "Your workouts sync automatically across devices signed into the same Apple Account. There is no separate login."
        }
    }

    private func eventText(_ event: CloudKitSyncMonitor.Event?) -> String {
        guard let event else { return "Never" }
        let time = event.date.formatted(date: .abbreviated, time: .shortened)
        return event.succeeded ? time : "\(time) (failed)"
    }

    private func refresh() {
        workoutCount = try? context.fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.deletedAt == nil }))
        sessionCount = try? context.fetchCount(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.deletedAt == nil }))

        // Uses the explicit container identifier rather than CKContainer.default(),
        // which derives from the bundle id and would only match here by coincidence.
        CKContainer(identifier: CloudKitContainer.identifier).accountStatus { status, _ in
            Task { @MainActor in accountStatus = status }
        }
    }
}
