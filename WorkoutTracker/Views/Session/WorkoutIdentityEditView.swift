import SwiftUI
import SwiftData

/// Edits a workout's name and description together. Reached via the pencil next to the
/// name (or "Add Description" when there's none yet) on `SessionRecapView`.
///
/// A genuinely separate view with its own `@State`, seeded once via `init`, the same
/// shape as `ExerciseIdentityEditView` — not a computed property reading the
/// presenter's own state seeded right before the sheet opens. That shape is what made
/// the Save button's `.disabled()` read a stale value on first presentation: only the
/// name field's own binding reliably refreshed it, so editing just the description did
/// nothing until the name was touched too.
struct WorkoutIdentityEditView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var errorMessage: String?

    init(workout: Workout) {
        self.workout = workout
        _name = State(initialValue: workout.name)
        _description = State(initialValue: workout.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Workout name", text: $name)
                }
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 160)
                }
            }
            .themedListBackground()
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedNotes = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try WorkoutEditingService.rename(workout, to: trimmedName, context: context)
            try WorkoutEditingService.updateNotes(workout, to: trimmedNotes.isEmpty ? nil : trimmedNotes, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
