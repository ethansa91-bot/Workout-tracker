import SwiftUI
import SwiftData

/// Creates a new record: picks the exercise (when opened from the Records list, which
/// has none fixed yet), the equipment, the execution type and the tracking mode, then
/// hands off to `RecordValueEditor` for the value itself.
///
/// The exercise/equipment/execution-type/tracking-mode selectors used to sit at the top
/// of the record page itself, always visible whether you were creating or correcting.
/// They now live only here, behind the record page's own "Add Record" button — a
/// correction to something that already exists doesn't need to re-ask what it already
/// knows.
struct AddPersonalRecordSheet: View {
    /// Which load a record belongs to. The same live cases as the runner's
    /// `WeightSource` — a typed weight is not one of them, it belongs to the equipment
    /// it was performed on — plus the legacy `.none`, for records saved before records
    /// were kept per equipment.
    private enum RecordSource: Hashable {
        case equipment(UUID)
        case bodyweight
        /// Records saved before records were kept per equipment. Offered in the menu
        /// only while it's already the selection, so it can be returned to but never
        /// newly chosen.
        case none
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil only until the exercise line picks one — always true when opened from the
    /// Records list, always false when opened from a specific exercise's own record page,
    /// which already knows which exercise this is.
    @State private var exercise: Exercise?
    @State private var source: RecordSource
    @State private var trackingMode: RepExerciseTrackingMode
    /// nil is the general record — the one every set files under until the exercise
    /// turns on `separateRecordsPerExecutionType`, and the only one that exists for an
    /// exercise that never will. A real choice on this page, not an unset state.
    @State private var executionType: ExecutionType?
    @State private var showingExercisePicker = false

    /// Kept so a record whose equipment has since been detached from the exercise still
    /// opens on the right one — `equipmentItems` would no longer resolve it.
    private let initialEquipment: Equipment?
    private let allowsExerciseChange: Bool
    /// Editing the load carried through a Follow Along step. Fixed for the life of the
    /// page rather than a selectable record type: a Follow Along record is reached by
    /// opening one, never by switching an existing rep record into one.
    private let isFollowAlong: Bool
    /// Called once a value is actually saved, so whatever opened this sheet can refresh
    /// its own list of records.
    var onSaved: (() -> Void)?

    init(
        exercise: Exercise? = nil,
        equipment: Equipment? = nil,
        isBodyweight: Bool = false,
        executionType: ExecutionType? = nil,
        trackingMode: RepExerciseTrackingMode = .repsWeight,
        isFollowAlong: Bool = false,
        onSaved: (() -> Void)? = nil
    ) {
        self.initialEquipment = equipment
        self.allowsExerciseChange = exercise == nil
        self.isFollowAlong = isFollowAlong
        self.onSaved = onSaved
        _exercise = State(initialValue: exercise)
        _executionType = State(initialValue: executionType)
        _trackingMode = State(initialValue: trackingMode)
        if isBodyweight {
            _source = State(initialValue: .bodyweight)
        } else if let equipment {
            _source = State(initialValue: .equipment(equipment.id))
        } else if let exercise, let resolved = exercise.defaultWeightedEquipment {
            _source = State(initialValue: .equipment(resolved.id))
        } else if exercise != nil {
            _source = State(initialValue: .bodyweight)
        } else {
            _source = State(initialValue: .none)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsExerciseChange {
                    GlassButtonRow(
                        systemImage: "figure.strengthtraining.traditional",
                        title: "Exercise",
                        value: exercise?.displayName ?? "Choose…"
                    ) {
                        showingExercisePicker = true
                    }
                    .formRow(isLast: false)
                }

                GlassMenuRow(
                    systemImage: isBodyweight ? "figure.strengthtraining.functional" : "dumbbell.fill",
                    title: "Equipment",
                    value: equipmentLabel,
                    isEnabled: exercise != nil
                ) {
                    equipmentMenu
                }
                .formRow(isLast: false)

                executionTypeRow

                // Not offered for a Follow Along record: its shape is decided by where
                // it came from, and switching it would silently open a different record.
                if !isFollowAlong {
                    GlassMenuRow(
                        systemImage: "trophy.fill",
                        title: "Record type",
                        value: trackingMode == .maxHoldTime ? "Max Time" : "Weight & Reps",
                        isEnabled: exercise != nil
                    ) {
                        Button("Weight & Reps") { trackingMode = .repsWeight }
                        Button("Max Time") { trackingMode = .maxHoldTime }
                    }
                    .formRow(isLast: false)
                }

                if let exercise {
                    RecordValueEditor(
                        exercise: exercise,
                        equipment: selectedEquipment,
                        isBodyweight: isBodyweight,
                        executionType: executionType,
                        trackingMode: trackingMode,
                        isFollowAlong: isFollowAlong,
                        existing: currentRecord,
                        context: context,
                        onSaved: { _ in
                            onSaved?()
                            dismiss()
                        }
                    )
                }
            }
            .fullBleedList()
            .safeAreaInset(edge: .top, spacing: 0) {
                PushedTitleBand(title: exercise?.displayName ?? "New Record")
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                // No `excluding:` — an exercise that already has a barbell record is
                // exactly the one you'd reach for to add a dumbbell one.
                ExercisePickerView { picked in
                    exercise = picked
                    source = defaultSource(for: picked)
                    // The previous exercise's type almost certainly isn't attached to
                    // this one, and carrying it over would resolve to a record nothing
                    // writes.
                    executionType = nil
                }
            }
        }
    }

    // MARK: - Selection

    /// Offered for an exercise that keeps records apart by type — and also whenever a
    /// type is already selected, even if the exercise has since stopped splitting.
    @ViewBuilder
    private var executionTypeRow: some View {
        if exercise?.splitsRecordsByExecutionType == true || executionType != nil {
            GlassMenuRow(
                systemImage: "bolt.fill",
                title: "Execution type",
                value: executionType?.name ?? "None",
                isEnabled: exercise != nil
            ) {
                Button("None") { executionType = nil }
                ForEach(executionTypeOptions) { type in
                    Button(type.name) { executionType = type }
                }
            }
            .formRow(isLast: false)
        }
    }

    /// The exercise's types, plus the current selection when it isn't among them — same
    /// one-way-door guard `equipmentOptions` applies, for a type detached since the
    /// record was set.
    private var executionTypeOptions: [ExecutionType] {
        guard let exercise else { return [] }
        var options = exercise.sortedExecutionTypes
        if let current = executionType, !options.contains(where: { $0.id == current.id }) {
            options.insert(current, at: 0)
        }
        return options
    }

    private var isBodyweight: Bool { source == .bodyweight }

    /// Looked up on the exercise, falling back to whatever the caller handed over — a
    /// record can outlive its equipment being detached, and it still has to open on it.
    private var selectedEquipment: Equipment? {
        guard case .equipment(let id) = source else { return nil }
        if let match = exercise?.equipmentItems.first(where: { $0.id == id }) { return match }
        return initialEquipment?.id == id ? initialEquipment : nil
    }

    /// The exercise's weighted equipment, plus the current selection when it isn't among
    /// them — otherwise switching away from an unusual record would be a one-way door.
    private var equipmentOptions: [Equipment] {
        guard let exercise else { return [] }
        var options = exercise.weightedEquipmentOptions
        if let current = selectedEquipment, !options.contains(where: { $0.id == current.id }) {
            options.insert(current, at: 0)
        }
        return options
    }

    @ViewBuilder
    private var equipmentMenu: some View {
        ForEach(equipmentOptions) { item in
            Button(item.name) { source = .equipment(item.id) }
        }
        if exercise?.allowsBodyweightSource == true || source == .bodyweight {
            Button("Bodyweight") { source = .bodyweight }
        }
        if source == RecordSource.none {
            Button("No equipment") { source = .none }
        }
    }

    private var equipmentLabel: String {
        switch source {
        case .bodyweight: return "Bodyweight"
        case .none: return "No equipment"
        case .equipment: return selectedEquipment?.name ?? "No equipment"
        }
    }

    private func defaultSource(for exercise: Exercise) -> RecordSource {
        if let resolved = exercise.defaultWeightedEquipment { return .equipment(resolved.id) }
        return .bodyweight
    }

    /// Re-resolved on every render rather than cached: the equipment/type/mode
    /// selection is what decides which record this sheet is correcting, and
    /// `RecordValueEditor` only re-seeds when this identity actually changes.
    private var currentRecord: PersonalRecord? {
        guard let exercise else { return nil }
        return PersonalRecordQueries.current(
            for: exercise,
            equipment: selectedEquipment,
            executionType: executionType,
            trackingMode: trackingMode,
            isBodyweight: isBodyweight,
            isFollowAlong: isFollowAlong,
            context: context
        )
    }
}
