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
    @State private var showingNewRecord = false

    /// One exercise's record on one equipment, of one shape. Several of these can belong
    /// to the same exercise; the list groups them into a single row.
    private struct Variant: Identifiable {
        let exercise: Exercise
        /// Which equipment this record belongs to — those lifts aren't comparable, so
        /// each keeps its own best.
        let equipment: Equipment?
        /// Weight/reps and max-time are separate achievements, so they're separate
        /// records rather than two readings of one.
        let trackingMode: RepExerciseTrackingMode
        let record: PersonalRecord?
        let derivedBestSet: SetLogQueries.BestSet?
        let derivedHold: Int?
        /// Best rep count achieved at body load. Bodyweight rows carry no equipment,
        /// so one exercise has exactly one of them however it was performed.
        var derivedBodyweightReps: Int? = nil
        var isBodyweight: Bool = false
        /// Composed so two equipment rows for one exercise stay distinct — and so a
        /// bodyweight row never collides with the weighted row for the same exercise.
        var id: String {
            "\(exercise.id)-\(isBodyweight ? "bodyweight" : (equipment?.id.uuidString ?? "none"))-\(trackingMode.rawValue)"
        }

        private var weightedEquipment: Equipment? {
            equipment ?? exercise.equipmentItems.first(where: \.isWeighted)
        }

        private var currentWeightValue: Double? {
            record?.weight ?? derivedBestSet?.weight
        }

        /// Level-based equipment only — the matching level's color, if any, shown as a
        /// small dot next to the summary text.
        var levelColor: PaletteColor? {
            guard let equipment = weightedEquipment, equipment.isLevelBased, let value = currentWeightValue else { return nil }
            return equipment.sortedWeightCombos.first(where: { $0.value == value })?.color
        }

        /// What the equipment line of the record page will read, so this row and that
        /// page name the same thing.
        var sourceLabel: String {
            isBodyweight ? "Bodyweight" : (equipment?.name ?? "No equipment")
        }

        var summary: String {
            // Saved records go through the shared formatter so this list, the record
            // page's history and the in-workout popup can't word the same record
            // differently. Derived bests have no record to hand it.
            if let record { return PersonalRecordFormatting.summary(record) }
            switch trackingMode {
            case .maxHoldTime:
                guard let derivedHold else { return "" }
                return "\(derivedHold)s"
            case .repsWeight:
                // No load to state — the achievement is the rep count. Same phrasing the
                // rep runner uses for a logged bodyweight set.
                if isBodyweight {
                    guard let derivedBodyweightReps else { return "" }
                    return "\(derivedBodyweightReps) × Bodyweight"
                }
                guard let derivedBestSet else { return "" }
                return "\(formattedWeight(derivedBestSet.weight)) × \(derivedBestSet.reps)"
            }
        }

        private func formattedWeight(_ value: Double) -> String {
            PersonalRecordFormatting.weight(
                value,
                unit: weightedEquipment?.effectiveWeightUnit,
                equipment: weightedEquipment
            )
        }
    }

    /// Keyed by exercise, equipment *and* record shape. Deliberately not
    /// `Dictionary(uniqueKeysWithValues:)`, which traps at runtime the moment two
    /// records share a key — with per-equipment records that's now an ordinary state,
    /// and previously it was a latent crash whenever sync produced a duplicate.
    private struct RecordKey: Hashable {
        let exerciseID: UUID
        let equipmentID: UUID?
        /// Bodyweight is the load, so which bar or rings it was done on doesn't change
        /// the achievement — those keys always carry a nil `equipmentID`.
        let isBodyweight: Bool
        /// A plank's best hold and a weighted plank's best set are different records and
        /// must not share a slot: keyed without this, promoting one destroyed the other.
        let trackingMode: RepExerciseTrackingMode
    }

    private var variants: [Variant] {
        var recordsByKey: [RecordKey: PersonalRecord] = [:]
        for record in allRecords {
            guard record.deletedAt == nil, let exerciseID = record.exercise?.id else { continue }
            let key = RecordKey(
                exerciseID: exerciseID,
                equipmentID: record.isBodyweight ? nil : record.equipment?.id,
                isBodyweight: record.isBodyweight,
                trackingMode: record.trackingMode
            )
            // Newest wins if duplicates ever appear, rather than crashing.
            if let existing = recordsByKey[key], existing.updatedAt >= record.updatedAt { continue }
            recordsByKey[key] = record
        }

        let setLogs = (try? context.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.isCancelled == false }
        ))) ?? []

        var bestSetByKey: [RecordKey: SetLogQueries.BestSet] = [:]
        var bestHoldByKey: [RecordKey: Int] = [:]
        var bestBodyweightRepsByKey: [RecordKey: Int] = [:]
        for log in setLogs {
            guard let exerciseID = log.exercise?.id else { continue }
            let isBodyweight = log.isBodyweight == true
            // A bodyweight set still records whichever equipment was selected, but that
            // isn't what the record is about — drop it so every bodyweight set for an
            // exercise lands on one key rather than splitting per bar/rings.
            let equipmentID = isBodyweight ? nil : log.equipment?.id
            if let hold = log.holdSeconds {
                let key = RecordKey(exerciseID: exerciseID, equipmentID: equipmentID, isBodyweight: isBodyweight, trackingMode: .maxHoldTime)
                if hold > (bestHoldByKey[key] ?? -1) {
                    bestHoldByKey[key] = hold
                }
                continue
            }
            let key = RecordKey(exerciseID: exerciseID, equipmentID: equipmentID, isBodyweight: isBodyweight, trackingMode: .repsWeight)
            if isBodyweight {
                // No load to compare — reps alone decide the best.
                if log.reps > (bestBodyweightRepsByKey[key] ?? -1) {
                    bestBodyweightRepsByKey[key] = log.reps
                }
            } else {
                let candidate = SetLogQueries.BestSet(weight: log.weight, reps: log.reps)
                let current = bestSetByKey[key]
                if current == nil || candidate.weight > current!.weight || (candidate.weight == current!.weight && candidate.reps > current!.reps) {
                    bestSetByKey[key] = candidate
                }
            }
        }

        let exercisesByID = Dictionary(allExercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let keys = Set(recordsByKey.keys)
            .union(bestSetByKey.keys)
            .union(bestHoldByKey.keys)
            .union(bestBodyweightRepsByKey.keys)

        return keys.compactMap { key -> Variant? in
            guard let exercise = exercisesByID[key.exerciseID], exercise.deletedAt == nil else { return nil }
            let equipment = key.equipmentID.flatMap { id in
                exercise.equipmentItems.first { $0.id == id }
            }
            return Variant(
                exercise: exercise,
                equipment: key.isBodyweight ? nil : equipment,
                trackingMode: key.trackingMode,
                record: recordsByKey[key],
                derivedBestSet: bestSetByKey[key],
                derivedHold: bestHoldByKey[key],
                derivedBodyweightReps: bestBodyweightRepsByKey[key],
                isBodyweight: key.isBodyweight
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
    /// them here — the list stays one line, and the record page's own equipment and
    /// record-type selectors reach the rest.
    private struct ExerciseRow: Identifiable {
        let exercise: Exercise
        let variants: [Variant]
        var id: UUID { exercise.id }

        /// Where the record page opens: the first variant, matching the order shown.
        var leadVariant: Variant? { variants.first }

        /// The line under the name: the single record, or a count when there are several
        /// behind the page's selectors.
        var summary: String {
            if let only = variants.first, variants.count == 1 { return only.summary }
            return "\(variants.count) records"
        }

        /// Nothing to delete when every variant is derived from session history — those
        /// aren't stored records and reappear the moment the list recomputes.
        var hasSavedRecord: Bool { variants.contains { $0.record != nil } }
    }

    private var rows: [ExerciseRow] {
        Dictionary(grouping: variants, by: { $0.exercise.id })
            .compactMap { _, group -> ExerciseRow? in
                guard let exercise = group.first?.exercise else { return nil }
                return ExerciseRow(
                    exercise: exercise,
                    variants: group.sorted { lhs, rhs in
                        if lhs.isBodyweight != rhs.isBodyweight { return lhs.isBodyweight }
                        if lhs.equipment?.name != rhs.equipment?.name {
                            return (lhs.equipment?.name ?? "") < (rhs.equipment?.name ?? "")
                        }
                        return lhs.trackingMode == .repsWeight
                    }
                )
            }
            .sorted { $0.exercise.name < $1.exercise.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageTitleBand(title: "Records")

                // Outside the Group below, so a search that matches nothing still leaves
                // the field on screen to clear or edit.
                searchField

                Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "No Records Yet",
                        systemImage: "trophy",
                        description: Text("Tap + to add a record for any exercise.")
                    )
                } else {
                    List {
                        ForEach(rows) { row in
                            NavigationLink {
                                editor(for: row)
                            } label: {
                                rowContent(row)
                            }
                            .swipeActions(edge: .trailing) {
                                if row.hasSavedRecord {
                                    Button(role: .destructive) {
                                        deleteRecords(row)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .fullBleedRow(isLast: row.id == rows.last?.id)
                        }
                    }
                    .fullBleedList()
                }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewRecord = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            // One sheet, not two: the record page picks the exercise itself, then the
            // equipment and the record type, on the same screen it saves from.
            .sheet(isPresented: $showingNewRecord) {
                PersonalRecordEditView(isPresentedAsSheet: true)
            }
        }
    }

    /// Hand-rolled rather than `.searchable`, which renders in the navigation bar — with
    /// the nav title emptied for the green band, that stranded the field in a bare bar
    /// above it.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appInkMuted)
            TextField("Search exercises", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appInkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        // A full-width band rather than a floating pill, so it reads as part of the page
        // the way the list rows below it do.
        .background(Color.appSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 0.5)
        }
    }

    private func rowContent(_ row: ExerciseRow) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: row.exercise.iconSymbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.displayName)
                HStack(spacing: 4) {
                    if row.variants.count == 1, let color = row.variants.first?.levelColor {
                        Circle().fill(color.color).frame(width: 6, height: 6)
                    }
                    Text(row.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Opens on the row's first variant; the page's own selectors reach the others, so
    /// there's no breakdown screen in between any more.
    private func editor(for row: ExerciseRow) -> some View {
        PersonalRecordEditView(
            exercise: row.exercise,
            equipment: row.leadVariant?.equipment,
            isBodyweight: row.leadVariant?.isBodyweight ?? false,
            trackingMode: row.leadVariant?.trackingMode ?? .repsWeight
        )
    }

    /// Removes every saved record for the exercise — the way a mistyped record gets
    /// corrected, since Save only ever accepts a value that beats the standing one.
    ///
    /// History goes with it: entries are only ever reached through `record.history`, so
    /// leaving them behind would strand them with nothing able to show or remove them.
    /// A row whose bests also come from session history reappears as a derived-only row,
    /// which is right — those sets really were logged.
    private func deleteRecords(_ row: ExerciseRow) {
        for variant in row.variants {
            guard let record = variant.record else { continue }
            for entry in record.history {
                SyncDeletion.delete(entry, context: context)
            }
            SyncDeletion.delete(record, context: context)
        }
        try? context.save()
    }
}
