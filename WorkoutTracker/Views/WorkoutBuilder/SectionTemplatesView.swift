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
    @State private var templatePendingDeletion: WorkoutSection?

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
                                templatePendingDeletion = section
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color.appDanger)
                        }
                    }
                }
                .themedListBackground()
            }
        }
        .background(Color.appBackground)
        .alert(
            "Delete \"\(templatePendingDeletion?.name ?? "")\"?",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let section = templatePendingDeletion {
                    deleteTemplate(section)
                }
                templatePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { templatePendingDeletion = nil }
        }
    }

    private func templateRow(_ section: WorkoutSection) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: section.sectionType.iconSymbolName)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.name?.isEmpty == false ? section.name! : section.sectionType.fallbackSectionName)
                StatusPill(text: section.sectionType.pillLabel, tint: .accentColor)
                if let description = section.sectionDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }


    private func deleteTemplate(_ section: WorkoutSection) {
        SyncDeletion.delete(section, context: context)
        try? context.save()
    }
}

/// Also reused by `SessionRecapView`'s "Create New Section" (with `title: "New
/// Section"`) to build a section attached to that workout instead of a standalone
/// template — same fields, same layout, just a different destination for `onCreate`.
struct NewSectionTemplateSheet: View {
    var title: String = "New Template"
    let onCreate: (String, String?, WorkoutSectionType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var type: WorkoutSectionType = .time

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Section name", text: $name)
                }
                Section("Description") {
                    TextField("Optional description", text: $description, axis: .vertical)
                }
                Section("Type") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach([WorkoutSectionType.time, .rep, .emom, .amrap], id: \.self) { option in
                            typeButton(option)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .themedListBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmedName, trimmedDescription.isEmpty ? nil : trimmedDescription, type)
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

    private func typeButton(_ option: WorkoutSectionType) -> some View {
        let isSelected = type == option
        return Button {
            type = option
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.iconSymbolName)
                    .font(.title2)
                Text(option.pillLabel)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .foregroundStyle(isSelected ? Color.white : Color.appAccent)
            .background(
                isSelected ? Color.appAccent : Color.appAccent.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.appAccent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
