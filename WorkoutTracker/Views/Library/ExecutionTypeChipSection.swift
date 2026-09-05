import SwiftUI
import SwiftData

/// The "Execution Types" section shared by the two exercise editors — the chip grid, the
/// inline "+ New" chip that creates a type from a name, and the "separate records" toggle
/// in the header.
///
/// One view rather than a copy in each editor, because the two disagree about everything
/// except the section itself: `ExerciseDetailView` writes straight through to a live
/// `Exercise`, while `CustomExerciseFormView` collects a `Set<UUID>` and applies it in
/// `save()`. Selection and creation come in as closures for that reason, the same shape as
/// each file's own `chipGrid` helper.
struct ExecutionTypeChipSection: View {
    @Query(filter: #Predicate<ExecutionType> { $0.deletedAt == nil }, sort: \ExecutionType.name)
    private var allTypes: [ExecutionType]

    let isSelected: (ExecutionType) -> Bool
    let toggle: (ExecutionType) -> Void
    /// Called with the freshly inserted type so the caller can attach it in whichever way
    /// it stores selection. The type is inserted and saved here — creating it is the same
    /// operation regardless of which editor asked.
    let onCreate: (ExecutionType) -> Void
    /// How many are currently selected. Drives the header toggle's visibility, and comes
    /// from the caller because only it knows about pending, unsaved selection.
    let selectedCount: Int
    /// nil hides the toggle entirely — the new-exercise form has no saved exercise to
    /// carry the flag on, so it collects it as plain state instead.
    var separateRecords: Binding<Bool>?

    @Environment(\.modelContext) private var context
    @State private var showingNewType = false
    @State private var newTypeName = ""

    var body: some View {
        Section {
            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(allTypes) { type in
                    SelectableChip(title: type.name, isSelected: isSelected(type), tint: .appStepPurple) {
                        toggle(type)
                    }
                }
                // Never selected, so `SelectableChip`'s selected-state icon swap can't
                // reach for a "plus.fill" that doesn't exist as a symbol.
                SelectableChip(icon: "plus", title: "New", isSelected: false, tint: .appInkMuted) {
                    newTypeName = ""
                    showingNewType = true
                }
            }
            .padding(.horizontal, HeaderMetrics.chipGutter)
            .padding(.vertical, 10)
            // On the row content, not on the `Section`: a presentation modifier attached
            // to a Section has no reliable view of its own to present from.
            .alert("New Execution Type", isPresented: $showingNewType) {
                TextField("e.g. Explosive", text: $newTypeName)
                Button("Create") { create() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Available to every exercise once created.")
            }
        } header: {
            ListBandHeader(title: "Execution Types") {
                // One attached type is already two buckets, because "no execution type"
                // never stops being a choice — a set logged without one files under the
                // untyped record, and that is a genuine split worth keeping apart.
                if let separateRecords, selectedCount >= 1 {
                    BandToggleButton(text: "Separate records", isOn: separateRecords.wrappedValue) {
                        separateRecords.wrappedValue.toggle()
                    }
                }
            }
        } footer: {
            FormSectionFooter(footerText)
        }
    }

    private var footerText: String {
        guard separateRecords != nil else {
            return "How the exercise is performed — explosive, slow, held. A workout picks one of these per exercise."
        }
        guard selectedCount >= 1 else {
            return "How the exercise is performed — explosive, slow, held. Attach one to keep separate records per type."
        }
        return "\"Separate records per type\" keeps a personal record for each type, plus one for sets logged without a type. Records already set stay as they are — they belong to no type, which stays a choice."
    }

    /// Reuses an existing type when the name matches one already in the catalog, rather
    /// than minting a second row with the same name. Two "Explosive"s would read as one
    /// choice offered twice and quietly split every record between them.
    private func create() {
        let trimmed = newTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = allTypes.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            if !isSelected(existing) { toggle(existing) }
            return
        }

        let type = ExecutionType(name: trimmed, isCustom: true)
        context.insert(type)
        try? context.save()
        onCreate(type)
    }
}
