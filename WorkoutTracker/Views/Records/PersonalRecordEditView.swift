import SwiftUI
import SwiftData

/// View/edit a single exercise's personal record. `existingRecord` is the current
/// manually-saved record, if any; when there isn't one yet, `derivedBestSet`/
/// `derivedHold` (computed by the caller from session history) prefill the form as
/// a starting point — saving always creates/updates a real, persisted
/// `PersonalRecord` from then on.
struct PersonalRecordEditView: View {
    let exercise: Exercise
    /// Which equipment this record belongs to — records are kept per equipment, so an
    /// exercise trained on two has one record each. nil falls back to the exercise's
    /// own resolution.
    var equipment: Equipment?
    var existingRecord: PersonalRecord?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var trackingMode: RepExerciseTrackingMode
    @State private var weight: Double
    @State private var reps: Int
    @State private var holdSeconds: Int
    /// Level-based equipment only: true when the weight doesn't match any of the
    /// equipment's current levels (or "Custom…" was explicitly picked), revealing a
    /// manual-entry field instead of the level picker's own value.
    @State private var useCustomWeight: Bool

    private var weightedEquipment: Equipment? {
        equipment ?? exercise.equipmentItems.first(where: \.isWeighted)
    }

    init(
        exercise: Exercise,
        equipment: Equipment? = nil,
        existingRecord: PersonalRecord? = nil,
        derivedBestSet: SetLogQueries.BestSet? = nil,
        derivedHold: Int? = nil
    ) {
        self.exercise = exercise
        self.equipment = equipment
        self.existingRecord = existingRecord
        _trackingMode = State(initialValue: existingRecord?.trackingMode ?? (derivedHold != nil && derivedBestSet == nil ? .maxHoldTime : .repsWeight))
        let initialWeight = existingRecord?.weight ?? derivedBestSet?.weight ?? 0
        _weight = State(initialValue: initialWeight)
        _reps = State(initialValue: existingRecord?.reps ?? derivedBestSet?.reps ?? 0)
        _holdSeconds = State(initialValue: existingRecord?.holdSeconds ?? derivedHold ?? 0)
        if let resolved = equipment ?? exercise.equipmentItems.first(where: \.isWeighted), resolved.isLevelBased {
            _useCustomWeight = State(initialValue: !resolved.sortedWeightCombos.contains { $0.value == initialWeight })
        } else {
            _useCustomWeight = State(initialValue: false)
        }
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
                    if let equipment = weightedEquipment, equipment.isLevelBased {
                        levelPicker(equipment)
                    } else {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField("Weight", value: $weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text(weightedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit).foregroundStyle(.secondary)
                        }
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

    @ViewBuilder
    private func levelPicker(_ equipment: Equipment) -> some View {
        Picker("Level", selection: levelSelection(equipment)) {
            ForEach(equipment.sortedWeightCombos) { combo in
                Text(combo.levelDisplayName).tag(Double?.some(combo.value))
            }
            Text("Custom…").tag(Double?.none)
        }
        if useCustomWeight {
            HStack {
                Text("Custom value")
                Spacer()
                TextField("Value", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
        }
    }

    private func levelSelection(_ equipment: Equipment) -> Binding<Double?> {
        Binding(
            get: { useCustomWeight ? nil : weight },
            set: { newValue in
                if let newValue {
                    useCustomWeight = false
                    weight = newValue
                } else {
                    useCustomWeight = true
                }
            }
        )
    }

    private func save() {
        let record = existingRecord ?? PersonalRecord(exercise: exercise, equipment: weightedEquipment)
        if existingRecord == nil {
            context.insert(record)
        }
        record.trackingMode = trackingMode
        switch trackingMode {
        case .repsWeight:
            record.weight = weight
            record.reps = reps
            record.holdSeconds = nil
            // Stamped rather than re-derived at display time, so the number keeps its
            // meaning if the exercise's equipment changes later.
            record.weightUnit = weightedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit
        case .maxHoldTime:
            record.holdSeconds = holdSeconds
            record.weight = nil
            record.reps = nil
            record.weightUnit = nil
        }
        record.markDirty()
        try? context.save()
        dismiss()
    }
}
