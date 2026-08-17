import SwiftUI
import SwiftData

struct RepSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let soundProfile: TimerSoundProfile
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var draftReps: [Int: Int] = [:]
    @State private var draftWeight: [Int: Double] = [:]
    @State private var draftHoldSeconds: [Int: Int] = [:]
    @State private var restStartSignal = 0
    @State private var restStopSignal = 0

    private var entries: [RepSectionExercise] { section.sortedRepExercises }
    private var currentIndex: Int { session.currentExerciseIndex ?? 0 }
    private var currentEntry: RepSectionExercise? {
        guard currentIndex >= 0, currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    var body: some View {
        if let entry = currentEntry, let exercise = entry.exercise {
            VStack(spacing: 0) {
                header(exercise: exercise, entry: entry)
                    .padding()
                Divider()
                GeometryReader { geometry in
                    if isWideLayout(geometry) {
                        wideBody(entry: entry, exercise: exercise)
                    } else {
                        compactBody(entry: entry, exercise: exercise)
                    }
                }
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom) {
                navigationBar(entry: entry)
            }
            .onAppear { primeDrafts(for: entry, exercise: exercise) }
            .onChange(of: entry.id) { _, _ in primeDrafts(for: entry, exercise: exercise) }
        } else {
            Color.clear.onAppear { onSectionComplete() }
        }
    }

    // MARK: - Layout pieces

    /// iPad in landscape (regular width, wider than tall) gets a two-column split —
    /// log on the left, media on the right, each scrolling independently — instead of
    /// one long single-column scroll. The header above stays fixed either way.
    private func isWideLayout(_ geometry: GeometryProxy) -> Bool {
        horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
    }

    private func compactBody(entry: RepSectionExercise, exercise: Exercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: 30))
                    .id(exercise.id)
                logColumn(entry: entry, exercise: exercise)
            }
            .padding()
        }
    }

    private func wideBody(entry: RepSectionExercise, exercise: Exercise) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                logColumn(entry: entry, exercise: exercise)
                    .padding()
            }
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: 30))
                    .id(exercise.id)
                    .padding()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func logColumn(entry: RepSectionExercise, exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            historyRow(entry: entry, exercise: exercise)
            setsSection(entry: entry, exercise: exercise)
            ExerciseNoteControl(session: session, exercise: exercise)
                .id(exercise.id)
        }
    }

    private func header(exercise: Exercise, entry: RepSectionExercise) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RestTimerView(
                totalSeconds: entry.customRestSeconds ?? AppSettings.defaultRestSeconds,
                soundProfile: soundProfile,
                isSessionActive: session.status == .inProgress,
                startSignal: $restStartSignal,
                stopSignal: $restStopSignal
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.displayName).font(.appSerif(.title3))
                if !exercise.equipmentItems.isEmpty {
                    Label(exercise.equipmentItems.map(\.name).joined(separator: ", "), systemImage: "dumbbell.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !exercise.muscles.isEmpty {
                    Text(exercise.muscles.map(\.name).sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let record = PersonalRecordQueries.current(for: exercise, context: context)
        switch entry.trackingMode {
        case .repsWeight:
            let maxSet: SetLogQueries.BestSet? = record.map { SetLogQueries.BestSet(weight: $0.weight ?? 0, reps: $0.reps ?? 0) }
                ?? SetLogQueries.bestSetEver(exercise: exercise, context: context)
            let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
            HStack(spacing: 16) {
                if let maxSet {
                    Label("Max \(maxSet.reps) × \(formattedWeight(maxSet.weight, exercise: exercise))", systemImage: "trophy.fill")
                }
                if let last {
                    Label("Last \(last.reps) × \(formattedWeight(last.weight, exercise: exercise))", systemImage: "clock.arrow.circlepath")
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

    private func setsSection(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let weightOptions = exercise.weightedEquipment?.sortedWeightCombos.map(\.value) ?? []
        let logs = loggedSets(for: entry)
        let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        let bestHold = entry.trackingMode == .maxHoldTime
            ? (PersonalRecordQueries.current(for: exercise, context: context)?.holdSeconds ?? SetLogQueries.bestHoldEver(exercise: exercise, context: context))
            : nil

        return VStack(alignment: .leading, spacing: 12) {
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
                            weightUnit: exercise.weightedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit,
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
        }
    }

    private enum NavDirection { case previous, next }

    /// Fixed height for the nav bar's `GeometryReader` (needed since GeometryReader has
    /// no intrinsic size of its own) — generous enough for the two-line button label
    /// (title + neighboring exercise name) at `.controlSize(.large)`.
    private static let navBarHeight: CGFloat = 64
    private static let navBarCornerRadius: CGFloat = 12

    private func navigationBar(entry: RepSectionExercise) -> some View {
        GeometryReader { geometry in
            let isBigScreen = horizontalSizeClass == .regular
            // Skip always occupies its slot in the layout — graying out instead of
            // disappearing when there's nothing left to skip, so Previous/Next don't
            // resize or shift position as sets get logged.
            let isSkipEnabled = loggedSets(for: entry).count < entry.targetSets
            let spacing: CGFloat = 12

            // Exact (not max) widths throughout, computed directly from geometry —
            // relying on flexible `.frame(maxWidth: .infinity)` buttons plus layout
            // priority to out-compete Spacers for leftover space turned out unreliable
            // in practice (buttons stayed small, Spacers ate the row instead). Exact
            // widths sidestep that: on iPhone they're sized to add up to the full row
            // width with no Spacers at all, so there's no leftover space stranded next
            // to Skip.
            HStack(spacing: spacing) {
                if isBigScreen {
                    // Capped at 25% of width — full-width buttons would look absurd on
                    // a big screen — with the slack visibly absorbed by Spacers.
                    let quarterWidth = geometry.size.width * 0.25
                    navButton(.previous, entry: entry, width: quarterWidth)
                    Spacer(minLength: 8)
                    skipButton(entry: entry, width: quarterWidth * 0.5, isEnabled: isSkipEnabled)
                    Spacer(minLength: 8)
                    navButton(.next, entry: entry, width: quarterWidth)
                } else {
                    // No Spacers — Previous/Next/Skip widths are sized to exactly fill
                    // the row themselves, Skip always half a side button's width.
                    let remaining = geometry.size.width - spacing * 2
                    let sideWidth = remaining / 2.5
                    navButton(.previous, entry: entry, width: sideWidth)
                    skipButton(entry: entry, width: sideWidth * 0.5, isEnabled: isSkipEnabled)
                    navButton(.next, entry: entry, width: sideWidth)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: Self.navBarHeight)
        .padding()
        .background(Color.appSurface)
    }

    private func skipButton(entry: RepSectionExercise, width: CGFloat, isEnabled: Bool) -> some View {
        Button(role: .destructive) {
            goToNext(entry: entry, force: true)
        } label: {
            // Smaller than Previous/Next's title font — Skip's width is always the
            // narrowest of the three, so it needs a font that fits at that width on
            // every screen size rather than the default (which could clip).
            Text("Skip")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: Self.navBarCornerRadius))
        .controlSize(.large)
        .tint(isEnabled ? Color.appDanger : Color.gray)
        // Explicit height (matching navButton's) rather than letting content size it —
        // guarantees Skip always matches Previous/Next exactly.
        .frame(width: width, height: Self.navBarHeight)
        .disabled(!isEnabled)
    }

    /// Previous/Next, each carrying a small subtitle (neighboring exercise name, or —
    /// at a section/workout boundary — the next section's name) so the button itself
    /// communicates what you're navigating to. `width` is exact (computed by the
    /// caller from available geometry), not a cap. An explicit `height` (rather than
    /// sizing to content) keeps every nav button the same height regardless of
    /// whether it has a subtitle to show; the subtitle line itself is only rendered
    /// when there's something to show, so a button without one (e.g. "Finish", or
    /// "Previous" on the very first exercise) centers its title in that height instead
    /// of sitting pinned above blank leftover space.
    private func navButton(_ direction: NavDirection, entry: RepSectionExercise, width: CGFloat) -> some View {
        let isPrevious = direction == .previous
        let isDisabled = isPrevious ? currentIndex == 0 : !canAdvance(entry)

        let title: String
        let subtitle: String?
        let icon: String?
        if isPrevious {
            title = "Previous"
            subtitle = previousExerciseName
            icon = "chevron.left"
        } else if !isLastExerciseInSection {
            title = "Next"
            subtitle = nextExerciseName
            icon = "chevron.right"
        } else if !isLastSection {
            title = "Next Section"
            subtitle = nextSectionName
            icon = "chevron.right"
        } else {
            title = "Finish"
            subtitle = nil
            icon = "checkmark"
        }

        return Button {
            if isPrevious { goToPrevious() } else { goToNext(entry: entry) }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if isPrevious { Image(systemName: icon!) }
                    Text(title)
                    if !isPrevious { Image(systemName: icon!) }
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // maxHeight: .infinity (not just maxWidth) is what actually centers a
            // single-line label within the button's full fixed height — without it the
            // VStack only fills width, keeping its natural (short) height and just
            // sitting near the top of the taller button instead of centering.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: Self.navBarCornerRadius))
        .controlSize(.large)
        .frame(width: width, height: Self.navBarHeight)
        .disabled(isDisabled)
    }

    private var previousExerciseName: String? {
        guard currentIndex > 0 else { return nil }
        return entries[currentIndex - 1].exercise?.displayName
    }

    private var nextExerciseName: String? {
        let next = currentIndex + 1
        guard next < entries.count else { return nil }
        return entries[next].exercise?.displayName
    }

    private var isLastExerciseInSection: Bool {
        currentIndex >= entries.count - 1
    }

    private var sections: [WorkoutSection] {
        session.workout?.sortedSections ?? []
    }

    private var currentSectionIndex: Int {
        sections.firstIndex(where: { $0.id == section.id }) ?? session.currentSectionIndex
    }

    private var isLastSection: Bool {
        currentSectionIndex >= sections.count - 1
    }

    private var nextSectionName: String? {
        guard !isLastSection else { return nil }
        let next = sections[currentSectionIndex + 1]
        return next.name?.isEmpty == false ? next.name! : next.sectionType.fallbackSectionName
    }

    // MARK: - Data helpers

    private func loggedSets(for entry: RepSectionExercise) -> [SetLog] {
        session.setLogs
            .filter { $0.repSectionExercise?.id == entry.id && !$0.isCancelled }
            .sorted { $0.setIndex < $1.setIndex }
    }

    private func canAdvance(_ entry: RepSectionExercise) -> Bool {
        loggedSets(for: entry).count >= entry.targetSets
    }

    private func isWorse(reps: Int, weight: Double, than last: SetLogQueries.BestSet?) -> Bool {
        guard let last else { return false }
        if weight < last.weight { return true }
        if weight == last.weight && reps < last.reps { return true }
        return false
    }

    private func formattedWeight(_ value: Double, exercise: Exercise) -> String {
        let unit = exercise.weightedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
    }

    private func primeDrafts(for entry: RepSectionExercise, exercise: Exercise) {
        draftReps.removeAll()
        draftWeight.removeAll()
        draftHoldSeconds.removeAll()
        let record = PersonalRecordQueries.current(for: exercise, context: context)
        let best = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        let weightOptions = exercise.weightedEquipment?.sortedWeightCombos.map(\.value) ?? []
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

    private func logSet(entry: RepSectionExercise, setIndex: Int) {
        restStartSignal += 1
        let reps = draftReps[setIndex] ?? 8
        let weight = draftWeight[setIndex] ?? 0
        let log = SetLog(
            session: session,
            repSectionExercise: entry,
            exercise: entry.exercise,
            exerciseNameSnapshot: entry.exercise?.displayName,
            setIndex: setIndex,
            reps: reps,
            weight: weight,
            weightUnit: entry.exercise?.weightedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit
        )
        context.insert(log)
        session.markDirty()
        try? context.save()
    }

    private func logHoldSet(entry: RepSectionExercise, setIndex: Int) {
        restStartSignal += 1
        let holdSeconds = draftHoldSeconds[setIndex] ?? 0
        let log = SetLog(
            session: session,
            repSectionExercise: entry,
            exercise: entry.exercise,
            exerciseNameSnapshot: entry.exercise?.displayName,
            setIndex: setIndex,
            reps: 0,
            weight: 0,
            weightUnit: entry.exercise?.weightedEquipment?.effectiveWeightUnit ?? AppSettings.weightUnit,
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

    private func goToNext(entry: RepSectionExercise, force: Bool = false) {
        guard force || canAdvance(entry) else { return }
        let next = currentIndex + 1
        if next < entries.count {
            session.currentExerciseIndex = next
        } else {
            session.markDirty()
            try? context.save()
            onSectionComplete()
            return
        }
        session.markDirty()
        try? context.save()
    }
}
