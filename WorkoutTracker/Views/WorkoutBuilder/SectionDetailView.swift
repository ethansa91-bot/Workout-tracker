import SwiftUI
import SwiftData

/// A single section on its own screen, in the same green-header-over-cards shape
/// `SessionRecapView` uses for a whole workout.
///
/// This is where a section template is built and edited. A template is just a
/// `WorkoutSection` with no parent workout, so it renders through the very same
/// `SectionCardView` an in-workout section does — it simply has no siblings, which is
/// what drops the position badge, Clone, Delete and Save-as-template while leaving
/// every exercise-level action intact.
struct SectionDetailView: View {
    @Bindable var section: WorkoutSection
    @Environment(\.modelContext) private var context

    @State private var showingSectionSettings = false
    // Owned here for the same reason `SessionRecapView` owns them: `SectionCardView`
    // takes them as bindings so its two halves can share one copy. This screen renders
    // the card whole, so plain state is enough.
    @State private var inSelectMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var showingBatchDeleteConfirm = false
    @State private var pendingDeleteItemID: UUID?
    @State private var errorMessage: String?
    @State private var showingEditSheet = false
    @State private var nameText = ""
    @State private var descriptionText = ""

    var body: some View {
        ScrollView {
            SectionCardView(
                section: section,
                // Nothing to collapse into — this section is the whole screen.
                isCollapsed: .constant(false),
                // No siblings: this section is the whole screen.
                siblings: nil,
                // The page header above already carries the name, summary and settings,
                // which would leave the card's own header row empty.
                showsHeader: false,
                showsCollapseControl: false,
                showsTitle: false,
                onError: { errorMessage = $0 },
                inSelectMode: $inSelectMode,
                selectedItemIDs: $selectedItemIDs,
                showingBatchDeleteConfirm: $showingBatchDeleteConfirm,
                pendingDeleteItemID: $pendingDeleteItemID
            )
        }
        .themedListBackground()
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) { editSheet }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Same full-width accent band as the workout screen's, so a section reads as the
    /// same kind of page one level down.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.appSerif(.title2))
                    .foregroundStyle(.white)
                Button {
                    nameText = section.name ?? ""
                    descriptionText = section.sectionDescription ?? ""
                    showingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Button {
                    showingSectionSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .popover(isPresented: $showingSectionSettings) {
                    // Clone and Delete are sibling-level actions; a template has no
                    // siblings, so the popover hides them.
                    SectionSettingsPopover(
                        section: section,
                        context: context,
                        onError: { errorMessage = $0 },
                        onClone: nil,
                        onDelete: nil
                    )
                }
            }
            Text("\(sectionKindSummary(section)) · \(sectionSettingsSummary(section))")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if let description = section.sectionDescription, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)
            }
        }
        .headerBandStyle()
    }

    private var title: String {
        if let name = section.name, !name.isEmpty { return name }
        return section.sectionType.fallbackSectionName
    }


    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Section name", text: $nameText)
                }
                Section("Description") {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 160)
                }
            }
            .themedListBackground()
            .navigationTitle("Edit Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdits() }
                }
            }
        }
    }

    private func saveEdits() {
        let trimmedName = nameText.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedName.isEmpty {
                try WorkoutEditingService.rename(section, to: trimmedName, context: context)
            }
            try WorkoutEditingService.updateDescription(section, to: trimmedDescription.isEmpty ? nil : trimmedDescription, context: context)
            showingEditSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
