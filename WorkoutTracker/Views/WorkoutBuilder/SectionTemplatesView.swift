import SwiftUI
import SwiftData

/// Reusable sections with no parent workout (`workout == nil`) — built here, then
/// imported (deep-copied) into any workout via "Import Template" in SessionRecapView's
/// "Add a Section" menu. Never locked, since there's no session history to protect.
/// Shown as one pane of WorkoutListView's horizontal selector, so it owns no
/// navigation title/toolbar of its own — creation is triggered from there.
struct SectionTemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSection.name) private var allSections: [WorkoutSection]

    private var templates: [WorkoutSection] {
        allSections.filter { $0.workout == nil && $0.deletedAt == nil }
    }

    var body: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No Section Templates Yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Save a section as a template from any workout, or tap + to build one here.")
                )
            } else {
                List {
                    ForEach(templates) { section in
                        NavigationLink {
                            SectionEditorView(section: section)
                        } label: {
                            templateRow(section)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTemplate(section)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .themedListBackground()
            }
        }
        .background(Color.appBackground)
    }

    private func templateRow(_ section: WorkoutSection) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: section.sectionType.iconSymbolName)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.name?.isEmpty == false ? section.name! : section.sectionType.fallbackSectionName)
                StatusPill(text: pillLabel(for: section.sectionType), tint: .accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func pillLabel(for type: WorkoutSectionType) -> String {
        switch type {
        case .time: return "Follow Along"
        case .rep: return "Rep"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        }
    }

    private func deleteTemplate(_ section: WorkoutSection) {
        SyncDeletion.delete(section, context: context)
        try? context.save()
    }
}

struct NewSectionTemplateSheet: View {
    let onCreate: (String, WorkoutSectionType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: WorkoutSectionType = .time

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Section name", text: $name)
                }
                Section("Type") {
                    Picker("Type", selection: $type) {
                        Text("Follow Along").tag(WorkoutSectionType.time)
                        Text("Rep").tag(WorkoutSectionType.rep)
                        Text("EMOM").tag(WorkoutSectionType.emom)
                        Text("AMRAP").tag(WorkoutSectionType.amrap)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .themedListBackground()
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(trimmedName, type)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }
}
