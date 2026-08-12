import SwiftUI
import SwiftData

struct RepExerciseFormView: View {
    let block: WorkoutBlock
    var editingEntry: RepBlockExercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExercise: Exercise?
    @State private var targetSets: Int
    @State private var restSeconds: Int
    @State private var trackingMode: RepExerciseTrackingMode
    @State private var headStartSeconds: Int
    @State private var showingExercisePicker = false
    @State private var errorMessage: String?

    init(block: WorkoutBlock, editingEntry: RepBlockExercise? = nil) {
        self.block = block
        self.editingEntry = editingEntry
        _selectedExercise = State(initialValue: editingEntry?.exercise)
        _targetSets = State(initialValue: editingEntry?.targetSets ?? 3)
        _restSeconds = State(initialValue: editingEntry?.customRestSeconds ?? AppSettings.defaultRestSeconds)
        _trackingMode = State(initialValue: editingEntry?.trackingMode ?? .repsWeight)
        _headStartSeconds = State(initialValue: editingEntry?.headStartSeconds ?? 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Button {
                    showingExercisePicker = true
                } label: {
                    HStack {
                        Text("Exercise")
                        Spacer()
                        Text(selectedExercise?.name ?? "Choose…").foregroundStyle(.secondary)
                    }
                }

                Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...20)

                Stepper("Rest: \(restSeconds)s", value: $restSeconds, in: 0...600, step: 15)

                Picker("Track by", selection: $trackingMode) {
                    Text("Reps & Weight").tag(RepExerciseTrackingMode.repsWeight)
                    Text("Max Hold Time").tag(RepExerciseTrackingMode.maxHoldTime)
                }
                .pickerStyle(.segmented)

                if trackingMode == .maxHoldTime {
                    Stepper("Head start: \(headStartSeconds)s", value: $headStartSeconds, in: 0...30)
                }
            }
            .themedListBackground()
            .navigationTitle(editingEntry == nil ? "Add Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedExercise == nil)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { selectedExercise = $0 }
            }
            .alert("Can't save", isPresented: Binding(
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
        guard let selectedExercise else { return }
        // Left at the default value, this saves as nil ("use default," tracking future
        // default changes) rather than freezing today's default as an explicit value.
        let rest: Int? = restSeconds == AppSettings.defaultRestSeconds ? nil : restSeconds
        do {
            if let editingEntry {
                guard let workout = block.workout, !workout.isLocked else { throw WorkoutEditingError.locked }
                editingEntry.exercise = selectedExercise
                editingEntry.targetSets = targetSets
                editingEntry.customRestSeconds = rest
                editingEntry.trackingMode = trackingMode
                editingEntry.headStartSeconds = headStartSeconds
                editingEntry.markDirty()
                try context.save()
            } else {
                try WorkoutEditingService.addRepExercise(
                    to: block,
                    exercise: selectedExercise,
                    targetSets: targetSets,
                    customRestSeconds: rest,
                    trackingMode: trackingMode,
                    headStartSeconds: headStartSeconds,
                    context: context
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
