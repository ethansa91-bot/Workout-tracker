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

    private struct Row: Identifiable {
        let exercise: Exercise
        let record: PersonalRecord?
        let derivedBestSet: SetLogQueries.BestSet?
        let derivedHold: Int?
        var id: UUID { exercise.id }

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
            let unit = exercise.equipmentItems.first(where: \.isWeighted)?.effectiveWeightUnit ?? AppSettings.weightUnit
            return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
        }
    }

    private var rows: [Row] {
        let recordsByExerciseID = Dictionary(uniqueKeysWithValues: allRecords.compactMap { record -> (UUID, PersonalRecord)? in
            guard record.deletedAt == nil, let exerciseID = record.exercise?.id else { return nil }
            return (exerciseID, record)
        })

        let setLogs = (try? context.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.isCancelled == false }
        ))) ?? []

        var bestSetByExerciseID: [UUID: SetLogQueries.BestSet] = [:]
        var bestHoldByExerciseID: [UUID: Int] = [:]
        for log in setLogs {
            guard let exerciseID = log.exercise?.id else { continue }
            if let hold = log.holdSeconds {
                if hold > (bestHoldByExerciseID[exerciseID] ?? -1) {
                    bestHoldByExerciseID[exerciseID] = hold
                }
            } else {
                let candidate = SetLogQueries.BestSet(weight: log.weight, reps: log.reps)
                let current = bestSetByExerciseID[exerciseID]
                if current == nil || candidate.weight > current!.weight || (candidate.weight == current!.weight && candidate.reps > current!.reps) {
                    bestSetByExerciseID[exerciseID] = candidate
                }
            }
        }

        return allExercises.compactMap { exercise -> Row? in
            guard exercise.deletedAt == nil else { return nil }
            let record = recordsByExerciseID[exercise.id]
            let derivedBestSet = bestSetByExerciseID[exercise.id]
            let derivedHold = bestHoldByExerciseID[exercise.id]
            guard record != nil || derivedBestSet != nil || derivedHold != nil else { return nil }
            return Row(exercise: exercise, record: record, derivedBestSet: derivedBestSet, derivedHold: derivedHold)
        }
        .filter { searchText.isEmpty
            || $0.exercise.name.localizedCaseInsensitiveContains(searchText)
            || ($0.exercise.label?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
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
                            PersonalRecordEditView(
                                exercise: row.exercise,
                                existingRecord: row.record,
                                derivedBestSet: row.derivedBestSet,
                                derivedHold: row.derivedHold
                            )
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

    private func rowContent(_ row: Row) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: row.exercise.iconSymbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.displayName)
                Text(row.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
