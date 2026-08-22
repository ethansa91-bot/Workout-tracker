import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Thin `FileDocument` around already-encoded JSON, so `.fileExporter` has something to
/// hand the system save panel. The encoding happens before the exporter opens — this
/// only carries bytes.
struct WorkoutExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Pick which workouts go into the exported file. Section templates aren't listed —
/// they're always included, since they're few and have no parent to choose from.
struct WorkoutExportPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.name) private var allWorkouts: [Workout]

    @State private var selectedIDs: Set<UUID> = []
    @State private var showingExporter = false
    @State private var document: WorkoutExportDocument?
    @State private var errorMessage: String?

    private var workouts: [Workout] {
        allWorkouts.filter { $0.deletedAt == nil }
    }

    private var selectedWorkouts: [Workout] {
        workouts.filter { selectedIDs.contains($0.id) }
    }

    private var allSelected: Bool {
        !workouts.isEmpty && selectedIDs.count == workouts.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts to Export",
                        systemImage: "square.and.arrow.up",
                        description: Text("Create a workout first.")
                    )
                } else {
                    List(workouts) { workout in
                        Button {
                            toggle(workout)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(workout.id) ? Color.appAccent : Color.appInkMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.name)
                                        .foregroundStyle(Color.appInk)
                                    Text(subtitle(for: workout))
                                        .font(.caption)
                                        .foregroundStyle(Color.appInkMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .themedListBackground()
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Export Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !workouts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            selectedIDs = allSelected ? [] : Set(workouts.map(\.id))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !workouts.isEmpty {
                    Button {
                        prepareExport()
                    } label: {
                        Text("Export (\(selectedIDs.count))")
                            .foregroundStyle(Color.appAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.appAccent.opacity(0.25))
                    .disabled(selectedIDs.isEmpty)
                    .padding()
                    .background(.thickMaterial)
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: document,
                contentType: .json,
                defaultFilename: defaultFilename
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

    private var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "workouts-\(formatter.string(from: .now))"
    }

    private func subtitle(for workout: Workout) -> String {
        let sections = workout.sortedSections.count
        return "\(sections) Section\(sections == 1 ? "" : "s") · \(workout.kind.rawValue)"
    }

    private func toggle(_ workout: Workout) {
        if selectedIDs.contains(workout.id) {
            selectedIDs.remove(workout.id)
        } else {
            selectedIDs.insert(workout.id)
        }
    }

    /// Encode first, then open the save panel — a failure here should surface as an
    /// alert rather than an empty file landing in Files.
    private func prepareExport() {
        do {
            let data = try WorkoutExportService.makeJSON(
                workouts: selectedWorkouts,
                templates: WorkoutExportService.allTemplates(context: context)
            )
            document = WorkoutExportDocument(data: data)
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
