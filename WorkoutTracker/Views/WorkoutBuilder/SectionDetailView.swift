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
    @State private var showingTagSheet = false
    @State private var nameText = ""
    @State private var descriptionText = ""

    var body: some View {
        ScrollView {
            card(part: .body)
        }
        .themedListBackground()
        // The band and the Select / Add Exercise row ride together as an inset rather
        // than as the top of the scroll stack, so a section's actions stay reachable
        // however far down its exercises you've scrolled — the same arrangement
        // `SessionRecapView` uses, reached through the card's own `Part` split.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header
                card(part: .header)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) { editSheet }
        .sheet(isPresented: $showingTagSheet) {
            WorkoutTagSheet(
                selection: Binding(
                    get: { section.sortedTags },
                    set: { try? WorkoutEditingService.setTags($0, on: section, context: context) }
                ),
                subjectName: "Template",
                subjectID: section.id
            )
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The two halves of the card, from one set of arguments.
    ///
    /// Both instances take the same bindings — which is exactly why `SectionCardView`
    /// asks for bindings rather than owning this state: the Select button lives in the
    /// header half and the row checkboxes in the body half, so `@State` inside the card
    /// would fork into two independent copies and leave the body permanently out of
    /// select mode.
    private func card(part: SectionCardView.Part) -> some View {
        SectionCardView(
            section: section,
            // Nothing to collapse into — this section is the whole screen.
            isCollapsed: .constant(false),
            // No siblings: this section is the whole screen.
            siblings: nil,
            part: part,
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

    /// Same full-width accent band as the workout screen's, so a section reads as the
    /// same kind of page one level down.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.appSerif(.title2))
                    .foregroundStyle(.white)
                // Hidden once the section is locked by its own record: the sheet it opens
                // saves through `WorkoutEditingService.rename`, which refuses, so the only
                // thing an editable-looking pencil could do here is produce an error.
                if !section.isLocked {
                    Button {
                        nameText = section.name ?? ""
                        descriptionText = section.sectionDescription ?? ""
                        showingEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }

                // Templates only: a section inside a workout is filed under that
                // workout's tags, so a second set here would be two answers to one
                // question.
                if section.isTemplate {
                    Button {
                        showingTagSheet = true
                    } label: {
                        Image(systemName: "tag")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Button {
                    showingSectionSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .sheet(isPresented: $showingSectionSettings) {
                    // Clone and Delete are sibling-level actions; a template has no
                    // siblings, so the panel hides them.
                    SectionSettingsPanel(
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

            HeaderTagPills(tags: section.sortedTags)

            if let description = section.sectionDescription, !description.isEmpty {
                // One line until tapped, like the workout header's — this band is pinned
                // over the exercise list and pays its height on every screenful.
                ExpandableBandText(text: description)
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
