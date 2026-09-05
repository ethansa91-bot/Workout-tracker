import SwiftUI
import SwiftData

/// Picks the tags on a workout or a section template: every existing tag as a chip, plus
/// an inline "New" that creates one from a name.
///
/// A sheet rather than an inline section, because it opens from the green header band
/// where there is no room for a chip grid — and because the same sheet serves both hosts.
/// Selection comes in and out as a plain `[WorkoutTag]` binding so each host saves the way
/// it already saves.
struct WorkoutTagSheet: View {
    @Binding var selection: [WorkoutTag]
    /// What the sheet is tagging, for the title — "Workout" or "Template".
    var subjectName: String
    /// The thing being tagged. Its own use of a tag doesn't count toward "still in use",
    /// since this sheet is where that use is being edited — see
    /// `CatalogDeletionService.deletionBlockReason(for:excluding:)`.
    var subjectID: UUID?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<WorkoutTag> { $0.deletedAt == nil }, sort: \WorkoutTag.name)
    private var allTags: [WorkoutTag]

    @State private var showingNewTag = false
    @State private var newTagName = ""
    @State private var deleteErrorMessage: String?
    @State private var tagPendingDelete: WorkoutTag?
    /// Set the instant a hold is recognized, so the tap that follows when the finger
    /// eventually lifts is known to belong to that hold rather than to a fresh, separate
    /// touch — see the note on the chip's gesture below.
    @State private var suppressNextTap = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(allTags) { tag in
                            SelectableChip(
                                icon: "tag",
                                title: tag.name,
                                isSelected: isSelected(tag),
                                tint: .appStepBlue
                            ) {
                                // A `simultaneousGesture` doesn't cancel the chip's own
                                // tap — it only guarantees both gestures see the touch —
                                // so holding long enough to open the delete alert still
                                // let the eventual finger-lift register as an ordinary
                                // tap underneath it, flipping the tag's selection at the
                                // same time. The flag is what actually stops that: it's
                                // set the moment the hold is recognized (mid-touch, not
                                // on release), which is always at or before this fires.
                                guard !suppressNextTap else {
                                    suppressNextTap = false
                                    return
                                }
                                toggle(tag)
                            }
                            // A `simultaneousGesture`, not `.contextMenu` and not
                            // `.onLongPressGesture`. A context menu inside a custom
                            // `Layout` binds its interaction to the container rather than
                            // to each subview, so the whole chip cloud lit up on a press
                            // and whichever tag the closure had captured was the one that
                            // got deleted — never the one being held. And a plain
                            // `.onLongPressGesture` never fires at all on a chip, because
                            // `SelectableChip` is a `Button` and a Button's own recognizer
                            // swallows it (see `RestTimerView`). A simultaneous gesture is
                            // the one form that both fires and stays with its own chip —
                            // the `suppressNextTap` flag above is what keeps it from also
                            // toggling selection.
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.45)
                                    .onEnded { _ in
                                        suppressNextTap = true
                                        tagPendingDelete = tag
                                    }
                            )
                        }
                        // Never selected, so the chip's selected-state icon swap can't
                        // reach for a "plus.fill" that isn't a symbol.
                        SelectableChip(icon: "plus", title: "New", isSelected: false, tint: .appInkMuted) {
                            newTagName = ""
                            showingNewTag = true
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Tags only help you find things — they never change how a workout runs, so they stay editable even once it's locked. Touch and hold a tag to delete it, once nothing else is using it.")
                }
            }
            .themedListBackground()
            .navigationTitle("Tag \(subjectName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Tag", isPresented: $showingNewTag) {
                TextField("e.g. push", text: $newTagName)
                Button("Create") { create() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Available to every workout and template once created.")
            }
            // Keyed on the tag itself, so what the alert names is always what was held.
            .alert(
                tagPendingDelete.map { "Delete \"\($0.name)\"?" } ?? "",
                isPresented: Binding(
                    get: { tagPendingDelete != nil },
                    set: { if !$0 { tagPendingDelete = nil } }
                ),
                presenting: tagPendingDelete
            ) { tag in
                // Offered only when nothing else needs it. When something does, the message
                // below says what — an alert that only says no would leave you guessing.
                if blockReason(tag) == nil {
                    Button("Delete", role: .destructive) { delete(tag) }
                }
                Button("Cancel", role: .cancel) { tagPendingDelete = nil }
            } message: { tag in
                Text(blockReason(tag) ?? "This removes the tag everywhere. Nothing else is using it.")
            }
            .alert("Can't Delete", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func blockReason(_ tag: WorkoutTag) -> String? {
        CatalogDeletionService.deletionBlockReason(for: tag, excluding: subjectID)
    }

    /// Deselects before deleting: the binding writes straight through to the host, so a
    /// tombstoned tag left in `selection` would stay in that relationship — invisible
    /// today, since every read filters `deletedAt`, but waiting to reappear if the row
    /// ever came back.
    private func delete(_ tag: WorkoutTag) {
        do {
            if isSelected(tag) { toggle(tag) }
            try CatalogDeletionService.delete(tag, excluding: subjectID, context: context)
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
        tagPendingDelete = nil
    }

    private func isSelected(_ tag: WorkoutTag) -> Bool {
        selection.contains { $0.id == tag.id }
    }

    private func toggle(_ tag: WorkoutTag) {
        if let index = selection.firstIndex(where: { $0.id == tag.id }) {
            selection.remove(at: index)
        } else {
            selection.append(tag)
        }
    }

    /// Reuses an existing tag when the name matches, rather than minting a second row with
    /// the same word — two "push" tags would split the very filter they exist to serve.
    private func create() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = allTags.first(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            if !isSelected(existing) { toggle(existing) }
            return
        }

        let tag = WorkoutTag(name: trimmed)
        context.insert(tag)
        try? context.save()
        selection.append(tag)
    }
}

/// The tags on a workout, rendered as pills inside the green header band.
///
/// A dedicated view rather than `SelectableChip`: that chip's unselected style is a faint
/// tint wash, which is invisible on the accent fill. Same problem the band's "Add
/// Description" control already solves by going white.
struct HeaderTagPills: View {
    let tags: [WorkoutTag]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
        }
    }
}
