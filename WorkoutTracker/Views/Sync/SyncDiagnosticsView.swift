import SwiftUI
import SwiftData
import CloudKit
import UIKit

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
                // Which CloudKit database this build actually talks to. Development and
                // Production have separate schemas, and a mismatch between them is the
                // single most confusing sync failure there is.
                LabeledContent("Environment") {
                    Text(environmentText)
                        .foregroundStyle(CloudKitEnvironment.isExplicitlyPinned ? Color.appDanger : Color.primary)
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
                    // Same formatter as the Activity rows: this error is just as likely
                    // to be a wrapper whose real cause is nested inside it.
                    Text(CloudKitErrorFormatter.describe(failure))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Why iCloud is unavailable")
                }
            }

            Section {
                activityRow("Last download", monitor.lastImport)
                activityRow("Last upload", monitor.lastExport)
                activityRow("Last setup", monitor.lastSetup)
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

            if !monitor.failures.isEmpty {
                Section {
                    ForEach(Array(monitor.failures.enumerated()), id: \.offset) { _, failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(failure.type) — \(failure.event.date.formatted(date: .abbreviated, time: .standard))")
                                .font(.footnote.monospaced())
                            Text(failure.event.detail ?? "No detail reported.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Failures this launch")
                } footer: {
                    Text("Every failure since the app started, newest first — CloudKit retries, and a later generic error would otherwise overwrite the one that named the cause.")
                }
            }

            Section {
                Button("Refresh") { refresh() }
                if !monitor.failures.isEmpty {
                    Button("Copy Diagnostics") { copyDiagnostics() }
                }
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

    private var environmentText: String {
        let environment = CloudKitEnvironment.current.rawValue
        // A pinned entitlement overrides the signing profile for every build, including
        // Xcode runs — flagged because it's almost always unintended.
        return CloudKitEnvironment.isExplicitlyPinned ? "\(environment) (forced)" : environment
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

    /// A failed event shows *why* underneath the timestamp. "(failed)" on its own gives
    /// no way to tell an undeployed Production schema from a signed-out account, which
    /// are the two failures that actually reach users.
    @ViewBuilder
    private func activityRow(_ title: String, _ event: CloudKitSyncMonitor.Event?) -> some View {
        if let event, !event.succeeded {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(title, value: eventText(event))
                Text(event.detail ?? "No error detail reported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            LabeledContent(title, value: eventText(event))
        }
    }

    private func eventText(_ event: CloudKitSyncMonitor.Event?) -> String {
        guard let event else { return "Never" }
        let time = event.date.formatted(date: .abbreviated, time: .shortened)
        return event.succeeded ? time : "\(time) (failed)"
    }

    /// The whole picture in one paste — status, counts, and every captured failure.
    private func copyDiagnostics() {
        var lines: [String] = [
            "WorkoutTracker sync diagnostics",
            "mode: \(ContainerStatus.isCloudEnabled ? "cloud" : "local-only")",
            "environment: \(environmentText)",
            "account: \(accountStatusText)",
            "network: \(reachability.isOnline ? "online" : "offline")",
            "workouts: \(workoutCount.map(String.init) ?? "?"), sessions: \(sessionCount.map(String.init) ?? "?")",
            "last setup: \(eventText(monitor.lastSetup))",
            "last import: \(eventText(monitor.lastImport))",
            "last export: \(eventText(monitor.lastExport))",
        ]
        if let failure = ContainerStatus.failure {
            lines.append("container failure: \(failure.domain) \(failure.code)")
            lines.append(CloudKitErrorFormatter.describe(failure))
        }
        for failure in monitor.failures {
            lines.append("")
            lines.append("[\(failure.type)] \(failure.event.date.formatted(date: .abbreviated, time: .standard))")
            lines.append(failure.event.detail ?? "No detail reported.")
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
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
