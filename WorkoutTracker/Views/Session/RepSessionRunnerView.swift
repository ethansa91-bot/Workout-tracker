import SwiftUI
import SwiftData

struct RepSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let block: WorkoutBlock
    let soundProfile: TimerSoundProfile
    let onBlockComplete: () -> Void

    @Environment(\.modelContext) private var context

    @State private var draftReps: [Int: Int] = [:]
    @State private var draftWeight: [Int: Double] = [:]
    @State private var draftHoldSeconds: [Int: Int] = [:]
    @State private var restStartSignal = 0
    @State private var restStopSignal = 0

    private var entries: [RepBlockExercise] { block.sortedRepExercises }
    private var currentIndex: Int { session.currentExerciseIndex ?? 0 }
    private var currentEntry: RepBlockExercise? {
        guard currentIndex >= 0, currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    var body: some View {
        if let entry = currentEntry, let exercise = entry.exercise {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(exercise: exercise, entry: entry)
                    historyRow(entry: entry, exercise: exercise)
                    setsSection(entry: entry, exercise: exercise)
                }
                .padding()
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom) {
                navigationBar(entry: entry)
            }
            .onAppear { primeDrafts(for: entry, exercise: exercise) }
            .onChange(of: entry.id) { _, _ in primeDrafts(for: entry, exercise: exercise) }
        } else {
            Color.clear.onAppear { onBlockComplete() }
        }
    }

    // MARK: - Layout pieces

    private func header(exercise: Exercise, entry: RepBlockExercise) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RestTimerView(
                totalSeconds: entry.customRestSeconds ?? AppSettings.defaultRestSeconds,
                soundProfile: soundProfile,
                startSignal: $restStartSignal,
                stopSignal: $restStopSignal
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name).font(.appSerif(.title3))
                if let equipmentName = exercise.equipment?.name {
                    Label(equipmentName, systemImage: "dumbbell.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !exercise.muscles.isEmpty {
                    Text(exercise.muscles.map(\.name).sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: exercise.iconSymbolName)
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func historyRow(entry: RepBlockExercise, exercise: Exercise) -> some View {
        let record = PersonalRecordQueries.current(for: exercise, context: context)
        switch entry.trackingMode {
        case .repsWeight:
            let maxSet: SetLogQueries.BestSet? = record.map { SetLogQueries.BestSet(weight: $0.weight ?? 0, reps: $0.reps ?? 0) }
                ?? SetLogQueries.bestSetEver(exercise: exercise, context: context)
            let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
            HStack(spacing: 16) {
                if let maxSet {
                    Label("Max \(maxSet.reps) × \(formattedWeight(maxSet.weight))", systemImage: "trophy.fill")
                }
                if let last {
                    Label("Last \(last.reps) × \(formattedWeight(last.weight))", systemImage: "clock.arrow.circlepath")
                }
                if maxSet == nil && last == nil {
                    Text("No history yet for this exercise").italic()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .maxHoldTime:
            let bestHold = record?.holdSeconds ?? SetLogQueries.bestHoldEver(exercise: exercise, context: context)
            let lastHold = SetLogQueries.lastHoldSeconds(exercise: exercise, excluding: session, context: context)
            HStack(spacing: 16) {
                if let bestHold {
                    Label("Best \(bestHold)s", systemImage: "trophy.fill")
                }
                if let lastHold {
                    Label("Last \(lastHold)s", systemImage: "clock.arrow.circlepath")
                }
                if bestHold == nil && lastHold == nil {
                    Text("No history yet for this exercise").italic()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func setsSection(entry: RepBlockExercise, exercise: Exercise) -> some View {
        let weightOptions = exercise.equipment?.sortedWeightCombos.map(\.value) ?? []
        let logs = loggedSets(for: entry)
        let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        let bestHold = entry.trackingMode == .maxHoldTime
            ? (PersonalRecordQueries.current(for: exercise, context: context)?.holdSeconds ?? SetLogQueries.bestHoldEver(exercise: exercise, context: context))
            : nil

        return VStack(spacing: 12) {
            ForEach(0..<entry.targetSets, id: \.self) { setIndex in
                switch entry.trackingMode {
                case .repsWeight:
                    if let log = logs.first(where: { $0.setIndex == setIndex }) {
                        SetRowView(
                            setNumber: setIndex + 1,
                            weightOptions: weightOptions,
                            weightUnit: log.weightUnit,
                            reps: .constant(log.reps),
                            weight: .constant(log.weight),
                            isLogged: true,
                            isWorseThanLast: isWorse(reps: log.reps, weight: log.weight, than: last),
                            onLog: {},
                            onCancel: { cancelSet(log) }
                        )
                    } else {
                        SetRowView(
                            setNumber: setIndex + 1,
                            weightOptions: weightOptions,
                            weightUnit: AppSettings.weightUnit,
                            reps: bindingReps(setIndex),
                            weight: bindingWeight(setIndex),
                            isLogged: false,
                            isWorseThanLast: false,
                            onLog: { logSet(entry: entry, setIndex: setIndex) },
                            onCancel: {}
                        )
                    }
                case .maxHoldTime:
                    if let log = logs.first(where: { $0.setIndex == setIndex }) {
                        HoldSetRowView(
                            setNumber: setIndex + 1,
                            headStartSeconds: entry.headStartSeconds,
                            previousBest: bestHold,
                            recordedSeconds: .constant(log.holdSeconds ?? 0),
                            isLogged: true,
                            onLog: {},
                            onCancel: { cancelSet(log) }
                        )
                        .id("\(entry.id)-\(setIndex)-logged")
                    } else {
                        HoldSetRowView(
                            setNumber: setIndex + 1,
                            headStartSeconds: entry.headStartSeconds,
                            previousBest: bestHold,
                            recordedSeconds: bindingHoldSeconds(setIndex),
                            isLogged: false,
                            onStart: { restStopSignal += 1 },
                            onLog: { logHoldSet(entry: entry, setIndex: setIndex) },
                            onCancel: {}
                        )
                        .id("\(entry.id)-\(setIndex)-pending")
                    }
                }
            }

            if logs.count < entry.targetSets {
                Button("Stop Sets", role: .destructive) {
                    goToNext(entry: entry, force: true)
                }
                .font(.footnote)
                .padding(.top, 4)
            }
        }
    }

    private func navigationBar(entry: RepBlockExercise) -> some View {
        HStack {
            Button {
                goToPrevious()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(currentIndex == 0)

            Spacer()

            Text(entry.exercise?.name ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                goToNext(entry: entry)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!canAdvance(entry))
        }
        .padding()
        .background(Color.appSurface)
    }

    // MARK: - Data helpers

    private func loggedSets(for entry: RepBlockExercise) -> [SetLog] {
        session.setLogs
            .filter { $0.repBlockExercise?.id == entry.id && !$0.isCancelled }
            .sorted { $0.setIndex < $1.setIndex }
    }

    private func canAdvance(_ entry: RepBlockExercise) -> Bool {
        loggedSets(for: entry).count >= entry.targetSets
    }

    private func isWorse(reps: Int, weight: Double, than last: SetLogQueries.BestSet?) -> Bool {
        guard let last else { return false }
        if weight < last.weight { return true }
        if weight == last.weight && reps < last.reps { return true }
        return false
    }

    private func formattedWeight(_ value: Double) -> String {
        let unit = AppSettings.weightUnit
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
    }

    private func primeDrafts(for entry: RepBlockExercise, exercise: Exercise) {
        draftReps.removeAll()
        draftWeight.removeAll()
        draftHoldSeconds.removeAll()
        let record = PersonalRecordQueries.current(for: exercise, context: context)
        let best = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        let weightOptions = exercise.equipment?.sortedWeightCombos.map(\.value) ?? []
        let defaultWeight: Double = record?.weight ?? best?.weight ?? weightOptions.first ?? 0
        let defaultReps: Int = record?.reps ?? best?.reps ?? 8
        for index in 0..<entry.targetSets {
            draftReps[index] = defaultReps
            draftWeight[index] = defaultWeight
            draftHoldSeconds[index] = 0
        }
    }

    private func bindingReps(_ index: Int) -> Binding<Int> {
        Binding(get: { draftReps[index] ?? 8 }, set: { draftReps[index] = $0 })
    }

    private func bindingWeight(_ index: Int) -> Binding<Double> {
        Binding(get: { draftWeight[index] ?? 0 }, set: { draftWeight[index] = $0 })
    }

    private func bindingHoldSeconds(_ index: Int) -> Binding<Int> {
        Binding(get: { draftHoldSeconds[index] ?? 0 }, set: { draftHoldSeconds[index] = $0 })
    }

    // MARK: - Actions

    private func logSet(entry: RepBlockExercise, setIndex: Int) {
        restStartSignal += 1
        let reps = draftReps[setIndex] ?? 8
        let weight = draftWeight[setIndex] ?? 0
        let log = SetLog(
            session: session,
            repBlockExercise: entry,
            exercise: entry.exercise,
            exerciseNameSnapshot: entry.exercise?.name,
            setIndex: setIndex,
            reps: reps,
            weight: weight,
            weightUnit: AppSettings.weightUnit
        )
        context.insert(log)
        session.markDirty()
        try? context.save()
    }

    private func logHoldSet(entry: RepBlockExercise, setIndex: Int) {
        restStartSignal += 1
        let holdSeconds = draftHoldSeconds[setIndex] ?? 0
        let log = SetLog(
            session: session,
            repBlockExercise: entry,
            exercise: entry.exercise,
            exerciseNameSnapshot: entry.exercise?.name,
            setIndex: setIndex,
            reps: 0,
            weight: 0,
            weightUnit: AppSettings.weightUnit,
            holdSeconds: holdSeconds
        )
        context.insert(log)
        session.markDirty()
        try? context.save()
    }

    private func cancelSet(_ log: SetLog) {
        log.isCancelled = true
        log.markDirty()
        try? context.save()
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        session.currentExerciseIndex = currentIndex - 1
        session.markDirty()
        try? context.save()
    }

    private func goToNext(entry: RepBlockExercise, force: Bool = false) {
        guard force || canAdvance(entry) else { return }
        let next = currentIndex + 1
        if next < entries.count {
            session.currentExerciseIndex = next
        } else {
            session.markDirty()
            try? context.save()
            onBlockComplete()
            return
        }
        session.markDirty()
        try? context.save()
    }
}
