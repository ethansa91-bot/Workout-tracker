import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Full-archive export: everything in the store plus the image bytes CloudKit can't
/// carry, as one `.zip`.
///
/// Distinct from `WorkoutExportPickerSheet`, which writes seed-format JSON for a chosen
/// subset of workouts. This one is all-or-nothing by design — it's a backup, and a
/// partial backup that looks complete is worse than none.
struct ArchiveExportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var includeSessionHistory = true
    @State private var isBuilding = false
    @State private var showingExporter = false
    @State private var document: ArchiveDocument?
    @State private var errorMessage: String?
    @State private var counts: (exercises: Int, workouts: Int, sessions: Int, images: Int)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include session history", isOn: $includeSessionHistory)
                } footer: {
                    Text("Your logged sets, timed steps, and per-exercise notes. Notes never sync through iCloud, so an archive is the only way to move them to another device.")
                }

                Section {
                    if let counts {
                        LabeledContent("Exercises", value: "\(counts.exercises)")
                        LabeledContent("Workouts", value: "\(counts.workouts)")
                        if includeSessionHistory {
                            LabeledContent("Sessions", value: "\(counts.sessions)")
                        }
                        LabeledContent("Generated images", value: "\(counts.images)")
                    } else {
                        ProgressView()
                    }
                } header: {
                    Text("What's included")
                } footer: {
                    Text("Custom exercises, equipment, personal records, workouts, and section templates are always included.")
                }
            }
            .themedListBackground()
            .navigationTitle("Export Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    prepareExport()
                } label: {
                    Group {
                        if isBuilding {
                            ProgressView()
                        } else {
                            Text("Export Archive")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBuilding)
                .padding()
                .background(.bar)
            }
            .task { counts = ArchiveExportService.previewCounts(context: context) }
            .fileExporter(
                isPresented: $showingExporter,
                document: document,
                contentType: .zip,
                defaultFilename: ArchiveExportService.defaultFilename()
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                } else {
                    dismiss()
                }
            }
            .alert("Export Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Build first, then open the save panel — same discipline as the workout exporter,
    /// so a failure surfaces as an alert instead of an empty file landing in Files.
    /// Zipping is heavier than encoding JSON, hence the progress state.
    private func prepareExport() {
        isBuilding = true
        Task {
            do {
                let url = try ArchiveExportService.makeArchive(
                    context: context,
                    includeSessionHistory: includeSessionHistory
                )
                document = ArchiveDocument(fileURL: url)
                isBuilding = false
                showingExporter = true
            } catch {
                isBuilding = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
