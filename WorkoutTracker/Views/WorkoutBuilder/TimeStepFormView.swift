import SwiftUI
import SwiftData

/// Add/edit a single time-section step — an exercise held for a duration, or a rest.
/// `stepType` is fixed for the lifetime of this form (chosen up front via "Add
/// Exercise"/"Add Rest") rather than a toggle inside the form, since the duration
/// field is identical either way and a type switch here would just be redundant chrome.
struct TimeStepFormView: View {
    let section: WorkoutSection
    let stepType: TimeStepType
    var editingStep: TimeSectionStep?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExercise: Exercise?
    @State private var durationSeconds: Int
    @State private var showingExercisePicker = false
    @State private var errorMessage: String?

    init(section: WorkoutSection, stepType: TimeStepType, editingStep: TimeSectionStep? = nil) {
        self.section = section
        self.stepType = stepType
        self.editingStep = editingStep
        _selectedExercise = State(initialValue: editingStep?.exercise)
        _durationSeconds = State(initialValue: editingStep?.durationSeconds ?? 30)
    }

    var body: some View {
        NavigationStack {
            Form {
                if stepType == .exercise {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        HStack {
                            Text("Exercise")
                            Spacer()
                            Text(selectedExercise?.name ?? "Choose…").foregroundStyle(.secondary)
                        }
                    }
                }

                Stepper("Duration: \(durationSeconds)s", value: $durationSeconds, in: durationRange, step: 5)
            }
            .themedListBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(stepType == .exercise && selectedExercise == nil)
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

    private var title: String {
        switch (stepType, editingStep == nil) {
        case (.exercise, true): return "Add Exercise"
        case (.exercise, false): return "Edit Exercise"
        case (.rest, true): return "Add Rest"
        case (.rest, false): return "Edit Rest"
        case (.getReady, true): return "Add Get Ready"
        case (.getReady, false): return "Edit Get Ready"
        }
    }

    private var durationRange: ClosedRange<Int> {
        stepType == .getReady ? 0...300 : 5...600
    }

    private func save() {
        do {
            if let editingStep {
                guard !section.isLocked else { throw WorkoutEditingError.locked }
                editingStep.exercise = stepType == .exercise ? selectedExercise : nil
                editingStep.durationSeconds = durationSeconds
                editingStep.markDirty()
                try context.save()
            } else {
                try WorkoutEditingService.addTimeStep(
                    to: section,
                    stepType: stepType,
                    exercise: stepType == .exercise ? selectedExercise : nil,
                    durationSeconds: durationSeconds,
                    context: context
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
