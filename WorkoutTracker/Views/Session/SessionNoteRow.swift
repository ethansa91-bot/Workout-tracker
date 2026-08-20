import SwiftUI
import SwiftData

/// The per-session note attached to the bottom of the Rep runner's set block.
///
/// Shows one note: this session's once written, otherwise the most recent earlier one,
/// so there's always something to read if the exercise has any history. Writing a note
/// replaces what's displayed — everything older stays reachable through the history
/// popup, newest first.
///
/// Distinct from `ExerciseNoteControl` (the Follow Along / summary control), which keeps
/// its own "last note above, this session below" layout.
struct SessionNoteRow: View {
    @Bindable var session: WorkoutSession
    let exercise: Exercise

    @Environment(\.modelContext) private var context
    @State private var showingEditor = false
    @State private var showingHistory = false
    @State private var isExpanded = false
    @State private var draftText = ""

    private var currentNote: ExerciseSessionNote? {
        session.exerciseNotes.first {
            $0.exercise?.id == exercise.id
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// What the row displays: this session's note, else the latest earlier one.
    private var displayedNote: ExerciseSessionNote? {
        currentNote ?? ExerciseSessionNoteQueries
            .pastNotes(for: exercise, excluding: session, context: context)
            .last
    }

    private var history: [ExerciseSessionNote] {
        ExerciseSessionNoteQueries.allNotes(for: exercise, context: context)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let displayedNote {
                noteTextRow(displayedNote)
            }
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingEditor) { editor }
        .sheet(isPresented: $showingHistory) { historySheet }
    }

    /// One line by default; tapping expands it in place rather than opening anything.
    private func noteTextRow(_ note: ExerciseSessionNote) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Text("\(Self.dateLabel(for: note.createdAt)) · \(note.text)")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(isExpanded ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !history.isEmpty {
                Button {
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionRow: some View {
        Button {
            draftText = currentNote?.text ?? ""
            showingEditor = true
        } label: {
            Label(currentNote == nil ? "Add note" : "Edit note",
                  systemImage: currentNote == nil ? "plus" : "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appAccent)
        }
        .buttonStyle(.plain)
    }

    private var editor: some View {
        NavigationStack {
            Form {
                TextEditor(text: $draftText)
                    .frame(minHeight: 160)
            }
            .themedListBackground()
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private var historySheet: some View {
        NavigationStack {
            List(history) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(note.text)
                        .font(.footnote)
                }
                .padding(.vertical, 2)
            }
            .themedListBackground()
            .navigationTitle("Note History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let note = ExerciseSessionNote.findOrCreate(session: session, exercise: exercise, context: context)
        note.text = draftText
        note.updatedAt = .now
        // Dirtying the session is what makes the new note appear immediately — see
        // `ExerciseNoteControl.saveNote` for the same reason.
        session.markDirty()
        try? context.save()
        showingEditor = false
        isExpanded = false
    }

    /// "Today" for the current session's note, an abbreviated date for anything older.
    private static func dateLabel(for date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "Today"
            : date.formatted(date: .abbreviated, time: .omitted)
    }
}
