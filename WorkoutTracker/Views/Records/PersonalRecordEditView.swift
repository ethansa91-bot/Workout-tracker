import SwiftUI
import SwiftData

/// View/edit a single exercise's personal record. `existingRecord` is the current
/// manually-saved record, if any; when there isn't one yet, `derivedBestSet`/
/// `derivedHold` (computed by the caller from session history) prefill the form as
/// a starting point — saving always creates/updates a real, persisted
/// `PersonalRecord` from then on.
struct PersonalRecordEditView: View {
    let exercise: Exercise
    var existingRecord: PersonalRecord?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var trackingMode: RepExerciseTrackingMode
    @State private var weight: Double
    @State private var reps: Int
    @State private var holdSeconds: Int

    init(
        exercise: Exercise,
        existingRecord: PersonalRecord? = nil,
        derivedBestSet: SetLogQueries.BestSet? = nil,
        derivedHold: Int? = nil
    ) {
        self.exercise = exercise
        self.existingRecord = existingRecord
        _trackingMode = State(initialValue: existingRecord?.trackingMode ?? (derivedHold != nil && derivedBestSet == nil ? .maxHoldTime : .repsWeight))
        _weight = State(initialValue: existingRecord?.weight ?? derivedBestSet?.weight ?? 0)
        _reps = State(initialValue: existingRecord?.reps ?? derivedBestSet?.reps ?? 0)
        _holdSeconds = State(initialValue: existingRecord?.holdSeconds ?? derivedHold ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DetailHeader(systemName: exercise.iconSymbolName, title: exercise.displayName)
                }

                Picker("Record type", selection: $trackingMode) {
                    Text("Weight & Reps").tag(RepExerciseTrackingMode.repsWeight)
                    Text("Max Hold Time").tag(RepExerciseTrackingMode.maxHoldTime)
                }
                .pickerStyle(.segmented)

                if trackingMode == .repsWeight {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("Weight", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(exercise.equipmentItems.first(where: \.isWeighted)?.effectiveWeightUnit ?? AppSettings.weightUnit).foregroundStyle(.secondary)
                    }
                    Stepper("Reps: \(reps)", value: $reps, in: 0...200)
                } else {
                    Stepper("Hold time: \(holdSeconds)s", value: $holdSeconds, in: 0...3600)
                }
            }
            .themedListBackground()
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let record = existingRecord ?? PersonalRecord(exercise: exercise)
        if existingRecord == nil {
            context.insert(record)
        }
        record.trackingMode = trackingMode
        switch trackingMode {
        case .repsWeight:
            record.weight = weight
            record.reps = reps
            record.holdSeconds = nil
        case .maxHoldTime:
            record.holdSeconds = holdSeconds
            record.weight = nil
            record.reps = nil
        }
        record.markDirty()
        try? context.save()
        dismiss()
    }
}
