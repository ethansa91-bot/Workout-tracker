import SwiftUI
import SwiftData

/// Drop-in "Add/Edit Note" control with a persistent "last note" preview and an
/// expandable full history (oldest to newest) — shared by every session runner (rep,
/// time, EMOM, AMRAP) so notes are managed identically regardless of section type.
/// `.id(exercise.id)` at each call site resets this view's local state (history
/// expanded, editor open) whenever the exercise it's showing changes.
struct ExerciseNoteControl: View {
    @Bindable var session: WorkoutSession
    let exercise: Exercise

    @Environment(\.modelContext) private var context
    @State private var showingNoteEditor = false
    @State private var noteText = ""
    @State private var isHistoryExpanded = false

    private var existingNote: ExerciseSessionNote? {
        session.exerciseNotes.first { $0.exercise?.id == exercise.id }
    }

    var body: some View {
        let past = ExerciseSessionNoteQueries.pastNotes(for: exercise, excluding: session, context: context)
        VStack(alignment: .leading, spacing: 10) {
            if let lastNote = past.last {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(lastNote.text)
                        .font(.footnote)
                        .foregroundStyle(Color.appInkMuted)
                }
            }

            HStack(spacing: 10) {
                Button {
                    noteText = existingNote?.text ?? ""
                    showingNoteEditor = true
                } label: {
                    Label(existingNote != nil ? "Edit Note" : "Add Note", systemImage: "note.text")
                }
                .buttonStyle(.bordered)

                if !past.isEmpty {
                    Button {
                        withAnimation { isHistoryExpanded.toggle() }
                    } label: {
                        Label("History", systemImage: isHistoryExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if isHistoryExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(past) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(note.text)
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .sheet(isPresented: $showingNoteEditor) {
            NavigationStack {
                Form {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 160)
                }
                .themedListBackground()
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingNoteEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveNote() }
                    }
                }
            }
        }
    }

    private func saveNote() {
        let note = ExerciseSessionNote.findOrCreate(session: session, exercise: exercise, context: context)
        note.text = noteText
        note.updatedAt = .now
        try? context.save()
        showingNoteEditor = false
    }
}
