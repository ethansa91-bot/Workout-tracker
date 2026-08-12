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
    @State private var restStartSignal = 0

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
                    historyRow(exercise: exercise)
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
                startSignal: $restStartSignal
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

    private func historyRow(exercise: Exercise) -> some View {
        let maxWeight = SetLogQueries.maxWeightEver(exercise: exercise, context: context)
        let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        return HStack(spacing: 16) {
            if let maxWeight {
                Label("Max \(formattedWeight(maxWeight))", systemImage: "trophy.fill")
            }
            if let last {
                Label("Last \(last.reps) × \(formattedWeight(last.weight))", systemImage: "clock.arrow.circlepath")
            }
            if maxWeight == nil && last == nil {
                Text("No history yet for this exercise").italic()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func setsSection(entry: RepBlockExercise, exercise: Exercise) -> some View {
        let weightOptions = exercise.equipment?.sortedWeightCombos.map(\.value) ?? []
        let logs = loggedSets(for: entry)
        let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)

        return VStack(spacing: 12) {
            ForEach(0..<entry.targetSets, id: \.self) { setIndex in
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
        let best = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        let weightOptions = exercise.equipment?.sortedWeightCombos.map(\.value) ?? []
        let defaultWeight = best?.weight ?? weightOptions.first ?? 0
        let defaultReps = best?.reps ?? 8
        for index in 0..<entry.targetSets {
            draftReps[index] = defaultReps
            draftWeight[index] = defaultWeight
        }
    }

    private func bindingReps(_ index: Int) -> Binding<Int> {
        Binding(get: { draftReps[index] ?? 8 }, set: { draftReps[index] = $0 })
    }

    private func bindingWeight(_ index: Int) -> Binding<Double> {
        Binding(get: { draftWeight[index] ?? 0 }, set: { draftWeight[index] = $0 })
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
