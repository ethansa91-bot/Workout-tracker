import SwiftUI
import SwiftData

/// Every exercise with a personal record — either a manually-saved `PersonalRecord`
/// or, absent one, the best result derived from session history (weight × reps, or
/// max hold time). Editing a derived-only row turns it into a real saved record.
struct RecordsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @Query private var allRecords: [PersonalRecord]

    @State private var searchText = ""
    @State private var showingPicker = false
    @State private var pendingNewExercise: Exercise?

    /// One exercise's record on one specific equipment. Several of these can belong to
    /// the same exercise; the list groups them into a single row.
    private struct Variant: Identifiable {
        let exercise: Exercise
        /// Which equipment this record belongs to — those lifts aren't comparable, so
        /// each keeps its own best.
        let equipment: Equipment?
        let record: PersonalRecord?
        let derivedBestSet: SetLogQueries.BestSet?
        let derivedHold: Int?
        /// Composed so two equipment rows for one exercise stay distinct.
        var id: String { "\(exercise.id)-\(equipment?.id.uuidString ?? "none")" }

        private var weightedEquipment: Equipment? {
            equipment ?? exercise.equipmentItems.first(where: \.isWeighted)
        }

        private var currentWeightValue: Double? {
            if let record, record.trackingMode == .repsWeight { return record.weight }
            return derivedBestSet?.weight
        }

        /// Level-based equipment only — the matching level's color, if any, shown as a
        /// small dot next to the summary text.
        var levelColor: PaletteColor? {
            guard let equipment = weightedEquipment, equipment.isLevelBased, let value = currentWeightValue else { return nil }
            return equipment.sortedWeightCombos.first(where: { $0.value == value })?.color
        }

        var summary: String {
            if let record {
                switch record.trackingMode {
                case .repsWeight:
                    return "\(formattedWeight(record.weight ?? 0)) × \(record.reps ?? 0)"
                case .maxHoldTime:
                    return "\(record.holdSeconds ?? 0)s hold"
                }
            } else if let derivedBestSet {
                return "\(formattedWeight(derivedBestSet.weight)) × \(derivedBestSet.reps)"
            } else if let derivedHold {
                return "\(derivedHold)s hold"
            }
            return ""
        }

        private func formattedWeight(_ value: Double) -> String {
            guard let equipment = weightedEquipment else {
                let unit = AppSettings.weightUnit
                return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
            }
            if equipment.isLevelBased {
                if let combo = equipment.sortedWeightCombos.first(where: { $0.value == value }) {
                    return combo.levelDisplayName
                }
                return "Level \(Int(value))"
            }
            let unit = equipment.effectiveWeightUnit
            return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
        }
    }

    /// Keyed by exercise *and* equipment. Deliberately not
    /// `Dictionary(uniqueKeysWithValues:)`, which traps at runtime the moment two
    /// records share a key — with per-equipment records that's now an ordinary state,
    /// and previously it was a latent crash whenever sync produced a duplicate.
    private struct RecordKey: Hashable {
        let exerciseID: UUID
        let equipmentID: UUID?
    }

    private var variants: [Variant] {
        var recordsByKey: [RecordKey: PersonalRecord] = [:]
        for record in allRecords {
            guard record.deletedAt == nil, let exerciseID = record.exercise?.id else { continue }
            let key = RecordKey(exerciseID: exerciseID, equipmentID: record.equipment?.id)
            // Newest wins if duplicates ever appear, rather than crashing.
            if let existing = recordsByKey[key], existing.updatedAt >= record.updatedAt { continue }
            recordsByKey[key] = record
        }

        let setLogs = (try? context.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.isCancelled == false }
        ))) ?? []

        var bestSetByKey: [RecordKey: SetLogQueries.BestSet] = [:]
        var bestHoldByKey: [RecordKey: Int] = [:]
        for log in setLogs {
            guard let exerciseID = log.exercise?.id else { continue }
            let key = RecordKey(exerciseID: exerciseID, equipmentID: log.equipment?.id)
            if let hold = log.holdSeconds {
                if hold > (bestHoldByKey[key] ?? -1) {
                    bestHoldByKey[key] = hold
                }
            } else if log.isBodyweight != true {
                let candidate = SetLogQueries.BestSet(weight: log.weight, reps: log.reps)
                let current = bestSetByKey[key]
                if current == nil || candidate.weight > current!.weight || (candidate.weight == current!.weight && candidate.reps > current!.reps) {
                    bestSetByKey[key] = candidate
                }
            }
        }

        let exercisesByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let keys = Set(recordsByKey.keys).union(bestSetByKey.keys).union(bestHoldByKey.keys)

        return keys.compactMap { key -> Variant? in
            guard let exercise = exercisesByID[key.exerciseID], exercise.deletedAt == nil else { return nil }
            let equipment = key.equipmentID.flatMap { id in
                exercise.equipmentItems.first { $0.id == id }
            }
            return Variant(
                exercise: exercise,
                equipment: equipment,
                record: recordsByKey[key],
                derivedBestSet: bestSetByKey[key],
                derivedHold: bestHoldByKey[key]
            )
        }
        .filter { searchText.isEmpty
            || $0.exercise.name.localizedCaseInsensitiveContains(searchText)
            || ($0.exercise.label?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        .sorted {
            $0.exercise.name == $1.exercise.name
                ? ($0.equipment?.name ?? "") < ($1.equipment?.name ?? "")
                : $0.exercise.name < $1.exercise.name
        }
    }

    /// One list row per exercise. An exercise trained on several equipment keeps all of
    /// them here — the list stays one line, and opening it shows each equipment's own
    /// record.
    private struct ExerciseRow: Identifiable {
        let exercise: Exercise
        let variants: [Variant]
        var id: UUID { exercise.id }

        var hasMultipleEquipment: Bool { variants.count > 1 }

        /// The line under the name: the single record, or a count when there are
        /// several to open.
        var summary: String {
            if let only = variants.first, variants.count == 1 { return only.summary }
            return "\(variants.count) equipment"
        }
    }

    private var rows: [ExerciseRow] {
        Dictionary(grouping: variants, by: { $0.exercise.id })
            .compactMap { _, group -> ExerciseRow? in
                guard let exercise = group.first?.exercise else { return nil }
                return ExerciseRow(
                    exercise: exercise,
                    variants: group.sorted { ($0.equipment?.name ?? "") < ($1.equipment?.name ?? "") }
                )
            }
            .sorted { $0.exercise.name < $1.exercise.name }
    }

    private var exerciseIDsWithRecord: Set<UUID> {
        Set(rows.map(\.exercise.id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "No Records Yet",
                        systemImage: "trophy",
                        description: Text("Tap + to add a record for any exercise.")
                    )
                } else {
                    List(rows) { row in
                        NavigationLink {
                            // One equipment goes straight to its record; several open a
                            // list so each equipment's own best is visible.
                            if row.hasMultipleEquipment {
                                variantList(row)
                            } else if let only = row.variants.first {
                                editor(for: only)
                            }
                        } label: {
                            rowContent(row)
                        }
                    }
                    .themedListBackground()
                }
            }
            .background(Color.appBackground)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(excluding: exerciseIDsWithRecord) { exercise in
                    pendingNewExercise = exercise
                }
            }
            .sheet(item: $pendingNewExercise) { exercise in
                PersonalRecordEditView(exercise: exercise)
            }
        }
    }

    private func rowContent(_ row: ExerciseRow) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: row.exercise.iconSymbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.displayName)
                HStack(spacing: 4) {
                    if !row.hasMultipleEquipment, let color = row.variants.first?.levelColor {
                        Circle().fill(color.color).frame(width: 6, height: 6)
                    }
                    Text(row.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// The per-equipment breakdown, shown when an exercise has been trained on more
    /// than one — each opens its own record.
    private func variantList(_ row: ExerciseRow) -> some View {
        List(row.variants) { variant in
            NavigationLink {
                editor(for: variant)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variant.equipment?.name ?? "No equipment")
                        HStack(spacing: 4) {
                            if let color = variant.levelColor {
                                Circle().fill(color.color).frame(width: 6, height: 6)
                            }
                            Text(variant.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .themedListBackground()
        .navigationTitle(row.exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func editor(for variant: Variant) -> some View {
        PersonalRecordEditView(
            exercise: variant.exercise,
            equipment: variant.equipment,
            existingRecord: variant.record,
            derivedBestSet: variant.derivedBestSet,
            derivedHold: variant.derivedHold
        )
    }
}
