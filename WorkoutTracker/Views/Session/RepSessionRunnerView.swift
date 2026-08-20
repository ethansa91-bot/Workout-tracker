import SwiftUI
import SwiftData

struct RepSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let soundProfile: TimerSoundProfile
    let onSectionComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Identifies one set slot. `side` is nil unless the entry tracks left/right, in
    /// which case each set index has two slots — the drafts, the active-slot search and
    /// the recap all key off this rather than a bare index.
    struct SetKey: Hashable {
        let index: Int
        let side: SetSide?
    }

    @State private var draftReps: [SetKey: Int] = [:]
    @State private var draftWeight: [SetKey: Double] = [:]
    @State private var draftHoldSeconds: [SetKey: Int] = [:]
    @State private var draftBodyweight: [SetKey: Bool] = [:]
    @State private var restStartSignal = 0
    @State private var restStopSignal = 0
    /// Briefly true after a save: the Save button is disabled and the set number is
    /// highlighted, so the change is visible before the card moves on.
    @State private var isSaving = false

    /// What an exercise's weight is being loaded with for this session. Session-local
    /// rather than persisted: the workout's own `preferredEquipment` is the default,
    /// and this is the in-the-moment override.
    enum WeightSource: Hashable {
        case equipment(UUID)
        /// Type the number in — for a loaded bar or a machine that isn't in the catalog.
        /// Offered for every exercise, not just ones with weighted equipment attached.
        case manual
        /// No external load. Weight logs as 0 and the steppers give way to a plain
        /// "Bodyweight" readout.
        case bodyweight
    }

    @State private var weightSourceByEntry: [UUID: WeightSource] = [:]

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
                    // Less above than around — the nav bar already sits directly over
                    // this, so a full pad on top just pushes the timer down the screen.
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom)
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
            // Only on a genuine exercise change. No `.onAppear` seeding: values resolve
            // on read, so re-entering the view (the wide/compact swap on rotation, for
            // one) can't wipe what's been carried forward.
            .onChange(of: entry.id) { _, _ in clearDrafts() }
        } else {
            Color.clear.onAppear { onSectionComplete() }
        }
    }

    // MARK: - Layout pieces

    /// Keyed to the size class rather than `isWideLayout` — that also requires
    /// landscape, which would collapse the description on an iPad held in portrait.
    private var descriptionStyle: ExerciseDescriptionView.Style {
        horizontalSizeClass == .compact ? .collapsible : .alwaysVisible
    }

    /// iPad in landscape (regular width, wider than tall) gets a two-column split —
    /// log on the left, media on the right, each scrolling independently — instead of
    /// one long single-column scroll. The header above stays fixed either way.
    private func isWideLayout(_ geometry: GeometryProxy) -> Bool {
        horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
    }

    private func compactBody(entry: RepSectionExercise, exercise: Exercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: 30), fillsWidth: true)
                    .id(exercise.id)
                ExerciseDescriptionView(exercise: exercise, style: descriptionStyle)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExerciseMediaView(exercise: exercise, mode: .autoplayWorkout(maxSeconds: 30), fillsWidth: true)
                        .id(exercise.id)
                    ExerciseDescriptionView(exercise: exercise, style: descriptionStyle)
                        .id(exercise.id)
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func logColumn(entry: RepSectionExercise, exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            setBlock(entry: entry, exercise: exercise)
        }
    }

    private func header(exercise: Exercise, entry: RepSectionExercise) -> some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                RestTimerView(
                    totalSeconds: entry.customRestSeconds ?? AppSettings.defaultRestSeconds,
                    soundProfile: soundProfile,
                    isSessionActive: session.status == .inProgress,
                    startSignal: $restStartSignal,
                    stopSignal: $restStopSignal
                )
                // A quarter of the row, so the timer keeps the same proportion on any
                // width rather than a fixed square that crowds a small phone.
                .frame(width: geometry.size.width * 0.33)

                VStack(alignment: .leading, spacing: 0) {
                    // Tinted band: which part of the workout you're in, set apart from
                    // the exercise details below it.
                    Text(sectionBannerText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
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
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(height: 132)
    }

    /// "Section: Abs 2 of 3" — the round is dropped when the section runs once.
    private var sectionBannerText: String {
        let total = section.effectiveRepeatCount
        guard total > 1 else { return "Section: \(section.displayName)" }
        return "Section: \(section.displayName) \(min(currentRepeat + 1, total)) of \(total)"
    }

    /// Everything about the set in one card: what it's loaded with, what the record is,
    /// the set controls, and the session note attached below a divider.
    private func setBlock(entry: RepSectionExercise, exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if entry.trackingMode == .repsWeight {
                equipmentLine(entry: entry, exercise: exercise)
            }
            recordLine(entry: entry, exercise: exercise)

            Divider()

            setsSection(entry: entry, exercise: exercise)

            Divider()

            SessionNoteRow(session: session, exercise: exercise)
                .id(exercise.id)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    /// Equipment name with a glass pencil menu — the same treatment "New Section" uses.
    /// Locked once a set is logged; cancelling them all unlocks it.
    private func equipmentLine(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let canEdit = canChangeEquipment(for: entry)
        return HStack(spacing: 8) {
            Image(systemName: isBodyweightSource(for: entry, exercise: exercise)
                  ? "figure.strengthtraining.functional"
                  : "dumbbell.fill")
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            Text(equipmentLabel(for: entry, exercise: exercise))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            GlassEffectContainer {
                Menu {
                    ForEach(weightedOptions(for: exercise)) { item in
                        Button(item.name) { select(.equipment(item.id), for: entry) }
                    }
                    if allowsBodyweightSource(for: entry, exercise: exercise) {
                        Button("Bodyweight") { select(.bodyweight, for: entry) }
                    }
                    Button("Manual entry") { select(.manual, for: entry) }
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(canEdit ? Color.appAccent : Color.secondary)
                }
                .buttonStyle(.glass)
                .disabled(!canEdit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The record for the equipment in use, with "last" appended only when there is one.
    @ViewBuilder
    private func recordLine(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let equipment = chosenEquipment(for: entry, exercise: exercise)
        let record = PersonalRecordQueries.current(for: exercise, equipment: equipment, context: context)

        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            Text(recordSummary(entry: entry, exercise: exercise, equipment: equipment, record: record))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordSummary(
        entry: RepSectionExercise,
        exercise: Exercise,
        equipment: Equipment?,
        record: PersonalRecord?
    ) -> String {
        switch entry.trackingMode {
        case .repsWeight:
            let best: SetLogQueries.BestSet? = record.map { SetLogQueries.BestSet(weight: $0.weight ?? 0, reps: $0.reps ?? 0) }
                ?? SetLogQueries.bestSetEver(exercise: exercise, equipment: equipment, context: context)
            let last = SetLogQueries.lastBestSet(exercise: exercise, equipment: equipment, excluding: session, context: context)
            guard let best else { return "No record set yet" }
            var text = "\(best.reps) × \(formattedWeight(best.weight, exercise: exercise))"
            if let last {
                text += " · last \(last.reps) × \(formattedWeight(last.weight, exercise: exercise))"
            }
            return text
        case .maxHoldTime:
            let bestHold = record?.holdSeconds ?? SetLogQueries.bestHoldEver(exercise: exercise, context: context)
            let lastHold = SetLogQueries.lastHoldSeconds(exercise: exercise, excluding: session, context: context)
            guard let bestHold else { return "No record set yet" }
            var text = "\(bestHold)s hold"
            if let lastHold { text += " · last \(lastHold)s" }
            return text
        }
    }


    private func select(_ source: WeightSource, for entry: RepSectionExercise) {
        weightSourceByEntry[entry.id] = source
        clearDrafts()
    }

    @ViewBuilder
    private func setsSection(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let weightOptions = activeWeightOptions(for: entry, exercise: exercise)
        let logs = loggedSets(for: entry)
        let last = SetLogQueries.lastBestSet(exercise: exercise, excluding: session, context: context)
        let bestHold = entry.trackingMode == .maxHoldTime
            ? (PersonalRecordQueries.current(for: exercise, context: context)?.holdSeconds ?? SetLogQueries.bestHoldEver(exercise: exercise, context: context))
            : nil

        if let key = activeSetKey(for: entry) {
            activeSetCard(
                entry: entry,
                exercise: exercise,
                key: key,
                weightOptions: weightOptions,
                bestHold: bestHold,
                logs: logs
            )
        } else if entry.isTrackingSides {
            // One row per set, both sides inside it — repeating "Set 2" for each side
            // reads as four sets rather than two.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<entry.targetSets, id: \.self) { index in
                    let sideLogs = SetSide.allCases.compactMap { side in
                        loggedSet(for: entry, key: SetKey(index: index, side: side), in: logs)
                            .map { (side, $0) }
                    }
                    if !sideLogs.isEmpty {
                        loggedSidePairRow(
                            setNumber: index + 1,
                            sideLogs: sideLogs,
                            exercise: exercise,
                            last: last
                        )
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(setKeys(for: entry), id: \.self) { key in
                    if let log = loggedSet(for: entry, key: key, in: logs) {
                        switch entry.trackingMode {
                        case .repsWeight:
                            SetRowView(
                                setNumber: key.index + 1,
                                weightOptions: weightOptions,
                                weightUnit: log.weightUnit,
                                reps: .constant(log.reps),
                                weight: .constant(log.weight),
                                isBodyweight: .constant(log.isBodyweight == true),
                                isLogged: true,
                                isWorseThanLast: log.isBodyweight == true
                                    ? false
                                    : isWorse(reps: log.reps, weight: log.weight, than: last),
                                onLog: {},
                                onCancel: { cancelSet(log) }
                            )
                        case .maxHoldTime:
                            HoldSetRowView(
                                setNumber: key.index + 1,
                                exerciseName: exercise.displayName,
                                headStartSeconds: entry.headStartSeconds,
                                previousBest: bestHold,
                                recordedSeconds: .constant(log.holdSeconds ?? 0),
                                isLogged: true,
                                onLog: {},
                                onCancel: { cancelSet(log) }
                            )
                            .id("\(entry.id)-\(key.index)-\(key.side?.rawValue ?? "both")-logged")
                        }
                    }
                }
            }
        }
    }

    /// A completed side-tracked set: the set number once, its two sides stacked tight
    /// beside it, and a single cancel that reopens the whole set for editing.
    private func loggedSidePairRow(
        setNumber: Int,
        sideLogs: [(SetSide, SetLog)],
        exercise: Exercise,
        last: SetLogQueries.BestSet?
    ) -> some View {
        HStack(spacing: 12) {
            Text("Set \(setNumber)")
                .font(.subheadline.weight(.medium))
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(sideLogs, id: \.0) { side, log in
                    let isWorseThanLast = log.isBodyweight != true
                        && isWorse(reps: log.reps, weight: log.weight, than: last)
                    HStack(spacing: 6) {
                        // Space is reserved whether or not the dot shows, so the two
                        // sides stay left-aligned with each other.
                        Circle()
                            .fill(isWorseThanLast ? Color.orange : Color.clear)
                            .frame(width: 6, height: 6)
                        Text(side.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .leading)
                        Text(loggedSetSummary(log, exercise: exercise))
                            .font(.subheadline.monospacedDigit())
                            .lineLimit(1)
                    }
                }
            }
            // Spread across the middle so the cancel button lands hard right on every
            // row, matching `SetRowView`'s compact recap.
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            Button {
                // Cancelling the set reopens both sides together, matching how they
                // were entered.
                sideLogs.forEach { cancelSet($0.1) }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.appDanger)

            Spacer(minLength: 0)
        }
        .opacity(0.7)
    }

    private func loggedSetSummary(_ log: SetLog, exercise: Exercise) -> String {
        let weightText = log.isBodyweight == true
            ? "Bodyweight"
            : formattedWeight(log.weight, exercise: exercise)
        return "\(weightText) × \(log.reps)"
    }

    private func activeSetCard(
        entry: RepSectionExercise,
        exercise: Exercise,
        key: SetKey,
        weightOptions: [WeightCombo],
        bestHold: Int?,
        logs: [SetLog]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activeSetTitle(entry: entry, key: key))
                .font(.appSerif(.title3))
                // Grows and greens for the moment after a save, so the set number that
                // just changed is what draws the eye.
                .foregroundStyle(isSaving ? Color.appAccent : Color.appInk)
                .scaleEffect(isSaving ? 1.12 : 1, anchor: .leading)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSaving)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch entry.trackingMode {
            case .repsWeight:
                if entry.isTrackingSides {
                    // Both sides on one card with a single Save — a side-tracked set is
                    // one unit of work, so it's entered and committed as one.
                    let keys = SetSide.allCases.map { SetKey(index: key.index, side: $0) }
                    VStack(spacing: 12) {
                        ForEach(keys, id: \.self) { sideKey in
                            // A side can already be logged here when only its partner was
                            // cancelled — show it as done rather than as a second empty row.
                            if let log = loggedSet(for: entry, key: sideKey, in: logs) {
                                SetRowView(
                                    setNumber: sideKey.index + 1,
                                    sideLabel: sideKey.side?.label,
                                    weightOptions: weightOptions,
                                    weightUnit: log.weightUnit,
                                    reps: .constant(log.reps),
                                    weight: .constant(log.weight),
                                    isBodyweight: .constant(log.isBodyweight == true),
                                    isLogged: true,
                                    isWorseThanLast: false,
                                    onLog: {},
                                    onCancel: { cancelSet(log) }
                                )
                            } else {
                                SetRowView(
                                    setNumber: sideKey.index + 1,
                                    sideLabel: sideKey.side?.label,
                                    weightMode: weightMode(for: entry, exercise: exercise),
                                    weightOptions: weightOptions,
                                    weightUnit: activeWeightUnit(for: entry, exercise: exercise),
                                    reps: bindingReps(sideKey, entry: entry, exercise: exercise),
                                    weight: bindingWeight(sideKey, entry: entry, exercise: exercise),
                                    isBodyweight: bindingBodyweight(sideKey, entry: entry, exercise: exercise),
                                    isLogged: false,
                                    isWorseThanLast: false,
                                    isProminent: true,
                                    allowsBodyweight: entry.allowsBodyweight,
                                    showsSaveButton: false,
                                    isSaving: isSaving,
                                    onLog: {},
                                    onCancel: {}
                                )
                            }
                        }

                        // Fill on the label — see `SetRowView.prominentBody` for why
                        // widening the Button itself leaves the title centered.
                        Button {
                            logBothSides(entry: entry, index: key.index)
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .disabled(isSaving)
                    }
                } else {
                    SetRowView(
                        setNumber: key.index + 1,
                        weightMode: weightMode(for: entry, exercise: exercise),
                        weightOptions: weightOptions,
                        weightUnit: activeWeightUnit(for: entry, exercise: exercise),
                        reps: bindingReps(key, entry: entry, exercise: exercise),
                        weight: bindingWeight(key, entry: entry, exercise: exercise),
                        isBodyweight: bindingBodyweight(key, entry: entry, exercise: exercise),
                        isLogged: false,
                        isWorseThanLast: false,
                        isProminent: true,
                        allowsBodyweight: entry.allowsBodyweight,
                        isSaving: isSaving,
                        onLog: { logSet(entry: entry, key: key) },
                        onCancel: {}
                    )
                }
            case .maxHoldTime:
                HoldSetRowView(
                    setNumber: key.index + 1,
                    exerciseName: exercise.displayName,
                    headStartSeconds: entry.headStartSeconds,
                    previousBest: bestHold,
                    recordedSeconds: bindingHoldSeconds(key),
                    isLogged: false,
                    isProminent: true,
                    isSaving: isSaving,
                    onStart: { restStopSignal += 1 },
                    onLog: { logHoldSet(entry: entry, key: key) },
                    onCancel: {}
                )
                // Distinct per set — HoldSetRowView keeps its own idle/stopped phase,
                // which must reset when the next set takes over this slot.
                .id("\(entry.id)-\(key.index)-\(key.side?.rawValue ?? "both")-pending")
            }
        }
        // No `.cardStyle()` here — the set controls live inside `setBlock`'s card, and
        // a second surface nested in the first read as a window within a window.
        .frame(maxWidth: .infinity)
        // Keyed on the whole slot: for a single-sided entry that's just the index, and
        // for a side-tracked one it also catches a cancel reopening one side of a pair.
        .onChange(of: key) { _, newKey in
            if entry.isTrackingSides {
                // Both sides are on screen together, so both drafts have to resolve
                // afresh when the card moves to a new set.
                for side in SetSide.allCases {
                    resetDraft(key: SetKey(index: newKey.index, side: side))
                }
            } else {
                resetDraft(key: newKey)
            }
        }
    }

    /// Both sides share one card, so the title stays a plain "Set 2 of 3" — each row
    /// inside carries its own Left/Right label.
    private func activeSetTitle(entry: RepSectionExercise, key: SetKey) -> String {
        "Set \(key.index + 1) of \(entry.targetSets)"
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
            let isSkipEnabled = loggedSets(for: entry).count < entry.totalSetSlots
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
        .padding(.horizontal)
        .padding(.top)
        // No bottom pad — the safe-area inset below already separates the bar from the
        // screen edge, so anything here is pure added height.
        .padding(.bottom, 0)
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

    /// True only when nothing follows — including this section's own remaining passes.
    /// Without the repeat check the button reads "Finish" on the last section while
    /// rounds 2 and 3 are still to come.
    private var isLastSection: Bool {
        guard !hasRemainingRepeats else { return false }
        return currentSectionIndex >= sections.count - 1
    }

    private var hasRemainingRepeats: Bool {
        currentRepeat + 1 < section.effectiveRepeatCount
    }

    private var nextSectionName: String? {
        // A remaining pass comes before any next section — and on the last section
        // there is no next index to read, so this must be checked first.
        if hasRemainingRepeats {
            return "Round \(currentRepeat + 2) of \(section.effectiveRepeatCount)"
        }
        guard currentSectionIndex + 1 < sections.count else { return nil }
        return sections[currentSectionIndex + 1].displayName
    }

    // MARK: - Data helpers

    private var currentRepeat: Int { session.currentSectionRepeat ?? 0 }

    // MARK: - Equipment choice

    /// Every weighted item attached to the exercise — the choices offered.
    private func weightedOptions(for exercise: Exercise) -> [Equipment] {
        exercise.equipmentItems.filter(\.isWeighted).sorted { $0.name < $1.name }
    }

    /// The session's choice, falling back to the workout's preference, then the
    /// exercise's own weighted equipment, and finally bodyweight when there is none.
    private func weightSource(for entry: RepSectionExercise, exercise: Exercise) -> WeightSource {
        if let chosen = weightSourceByEntry[entry.id] { return chosen }
        if let preferred = entry.preferredEquipment { return .equipment(preferred.id) }
        if let first = weightedOptions(for: exercise).first { return .equipment(first.id) }
        return .bodyweight
    }

    private func chosenEquipment(for entry: RepSectionExercise, exercise: Exercise) -> Equipment? {
        guard case .equipment(let id) = weightSource(for: entry, exercise: exercise) else { return nil }
        return weightedOptions(for: exercise).first { $0.id == id }
    }

    private func isManualEntry(for entry: RepSectionExercise, exercise: Exercise) -> Bool {
        weightSource(for: entry, exercise: exercise) == .manual
    }

    /// True when nothing is loaded — the sets show "Bodyweight" instead of a stepper.
    private func isBodyweightSource(for entry: RepSectionExercise, exercise: Exercise) -> Bool {
        weightSource(for: entry, exercise: exercise) == .bodyweight
    }

    /// Whether bodyweight is a legitimate choice for this exercise: flagged for it in
    /// the catalog, or simply having no weighted equipment to load.
    private func allowsBodyweightSource(for entry: RepSectionExercise, exercise: Exercise) -> Bool {
        weightedOptions(for: exercise).isEmpty || exercise.allowsBodyweight
    }

    /// How each set's weight control should render, given the exercise's source.
    private func weightMode(for entry: RepSectionExercise, exercise: Exercise) -> SetRowView.WeightMode {
        switch weightSource(for: entry, exercise: exercise) {
        case .manual: return .manual
        case .bodyweight: return .bodyweight
        case .equipment: return .stepper
        }
    }

    /// The weight a set would log right now — the typed number in manual mode, zero for
    /// bodyweight, otherwise the stepper's draft.
    private func resolvedWeight(entry: RepSectionExercise, exercise: Exercise, key: SetKey) -> (weight: Double, isBodyweight: Bool) {
        switch weightSource(for: entry, exercise: exercise) {
        case .bodyweight:
            return (0, true)
        case .manual:
            // Same draft the wheel edits — so it prefills from the record and carries
            // forward from the previous set exactly like a stepper set does. Floored at
            // the wheel's own minimum: a loaded set weighing nothing is a bodyweight
            // set, which is a separate source.
            let manual = draftValues(entry: entry, exercise: exercise, key: key).weight
            return (max(WeightWheelPicker.minimumValue, manual), false)
        case .equipment:
            let values = draftValues(entry: entry, exercise: exercise, key: key)
            return (values.isBodyweight ? 0 : values.weight, values.isBodyweight)
        }
    }

    /// Locked once anything is logged for this exercise in this pass — the sets already
    /// recorded belong to the equipment that was chosen when they were made. Cancelling
    /// every set unlocks it again.
    private func canChangeEquipment(for entry: RepSectionExercise) -> Bool {
        loggedSets(for: entry).isEmpty
    }

    private func equipmentLabel(for entry: RepSectionExercise, exercise: Exercise) -> String {
        switch weightSource(for: entry, exercise: exercise) {
        case .manual: return "Manual entry"
        case .bodyweight: return "Bodyweight"
        case .equipment: return chosenEquipment(for: entry, exercise: exercise)?.name ?? "Bodyweight"
        }
    }

    /// The unit that a set logged right now would carry.
    private func activeWeightUnit(for entry: RepSectionExercise, exercise: Exercise) -> String {
        if isManualEntry(for: entry, exercise: exercise) { return AppSettings.weightUnit }
        return chosenEquipment(for: entry, exercise: exercise)?.effectiveWeightUnit ?? AppSettings.weightUnit
    }

    private func activeWeightOptions(for entry: RepSectionExercise, exercise: Exercise) -> [WeightCombo] {
        guard case .equipment = weightSource(for: entry, exercise: exercise) else { return [] }
        return chosenEquipment(for: entry, exercise: exercise)?.sortedWeightCombos ?? []
    }

    /// Scoped to the current pass. On a repeated section the earlier passes' logs are
    /// still on the session, and counting them would make every slot look filled — the
    /// runner would show the recap and refuse to log a single set on round 2. Every
    /// slot/advance/carryover helper derives from this, so the scoping lives here only.
    private func loggedSets(for entry: RepSectionExercise) -> [SetLog] {
        session.setLogs
            .filter { $0.repSectionExercise?.id == entry.id && !$0.isCancelled && $0.repeatIndex == currentRepeat }
            .sorted { $0.setIndex < $1.setIndex }
    }

    private func canAdvance(_ entry: RepSectionExercise) -> Bool {
        loggedSets(for: entry).count >= entry.totalSetSlots
    }

    /// Every slot this entry expects, in the order they're worked through — for a
    /// side-tracked entry that's Set 1 Left, Set 1 Right, Set 2 Left, and so on.
    private func setKeys(for entry: RepSectionExercise) -> [SetKey] {
        guard entry.isTrackingSides else {
            return (0..<entry.targetSets).map { SetKey(index: $0, side: nil) }
        }
        return (0..<entry.targetSets).flatMap { index in
            SetSide.allCases.map { SetKey(index: index, side: $0) }
        }
    }

    /// The set being worked on right now: the first slot with no live log. `nil` once
    /// every slot is filled, which is what swaps the single focused card for the
    /// all-sets recap.
    ///
    /// Derived rather than stored so it survives pause/resume and reacts to a cancel for
    /// free — cancelling a set in the middle reopens exactly that slot, and saving it
    /// again lands straight back on the recap.
    private func activeSetKey(for entry: RepSectionExercise) -> SetKey? {
        let logged = Set(loggedSets(for: entry).map { SetKey(index: $0.setIndex, side: $0.side) })
        return setKeys(for: entry).first { !logged.contains($0) }
    }

    private func loggedSet(for entry: RepSectionExercise, key: SetKey, in logs: [SetLog]) -> SetLog? {
        logs.first { $0.setIndex == key.index && $0.side == key.side }
    }

    /// What a pending set should start from, in priority order:
    ///  1. this slot's own cancelled log — reopening a set you just cancelled should let
    ///     you correct it, not retype it from scratch;
    ///  2. the nearest logged set before it — each set starts where the last one landed,
    ///     so a heavier or lighter working set carries forward instead of snapping back
    ///     to the all-time record;
    ///  3. `nil`, leaving `recordSeed` to supply the value (set 1's usual case).
    ///
    /// Reads `session.setLogs` directly rather than `SetLogQueries` — those exclude the
    /// current session by design, so they can't see the sets just logged.
    ///
    /// With sides tracked, each side carries its own thread: the right leg's set 2 seeds
    /// from the right leg's set 1, falling back to the other side only when this one has
    /// no history yet (so set 1 Right still starts from set 1 Left rather than the
    /// all-time record).
    private func carryoverValues(for entry: RepSectionExercise, key: SetKey) -> (reps: Int, weight: Double, isBodyweight: Bool)? {
        guard entry.trackingMode == .repsWeight else { return nil }
        // Scoped to this pass like `loggedSets` — a repeated section should start each
        // round from the record, not silently inherit the previous round's last set.
        let logs = session.setLogs.filter {
            $0.repSectionExercise?.id == entry.id && $0.repeatIndex == currentRepeat
        }

        if let cancelled = logs
            .filter({ $0.setIndex == key.index && $0.side == key.side && $0.isCancelled })
            .max(by: { $0.loggedAt < $1.loggedAt }) {
            return (cancelled.reps, cancelled.weight, cancelled.isBodyweight == true)
        }

        let live = logs.filter { !$0.isCancelled }

        if let previousSameSide = live
            .filter({ $0.side == key.side && $0.setIndex < key.index })
            .max(by: { $0.setIndex < $1.setIndex }) {
            return (previousSameSide.reps, previousSameSide.weight, previousSameSide.isBodyweight == true)
        }

        // Deliberately no cross-side fallback. Both sides are entered on one card and
        // saved together, and `logBothSides` writes left first — so falling back to
        // "most recently logged" would resolve an untouched right side to the left's
        // value the instant it was inserted, silently copying one side onto the other.
        // Each side carries its own thread, or defers to the record.
        return nil
    }

    /// Clears any stale draft for a set as it becomes active, so `draftValues` resolves
    /// it afresh from the carryover (or the record). Clearing rather than assigning is
    /// what keeps the displayed value independent of view lifecycle callbacks.
    private func resetDraft(key: SetKey) {
        draftReps[key] = nil
        draftWeight[key] = nil
        draftBodyweight[key] = nil
    }

    private func isWorse(reps: Int, weight: Double, than last: SetLogQueries.BestSet?) -> Bool {
        guard let last else { return false }
        if weight < last.weight { return true }
        if weight == last.weight && reps < last.reps { return true }
        return false
    }

    private func formattedWeight(_ value: Double, exercise: Exercise) -> String {
        guard let equipment = exercise.weightedEquipment else {
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

    /// The starting point for an exercise's first set: the personal record, then the
    /// best set from the last time this exercise was trained, then the lightest weight
    /// the equipment offers.
    private func recordSeed(for exercise: Exercise, entry: RepSectionExercise? = nil) -> (reps: Int, weight: Double) {
        // Seeded from the same equipment the set will be logged on, so switching
        // equipment re-seeds from that equipment's own history.
        let equipment = entry.flatMap { chosenEquipment(for: $0, exercise: exercise) }
        let record = PersonalRecordQueries.current(for: exercise, equipment: equipment, context: context)
        let best = SetLogQueries.lastBestSet(exercise: exercise, equipment: equipment, excluding: session, context: context)
        let weightOptions = (equipment ?? exercise.weightedEquipment)?.sortedWeightCombos.map(\.value) ?? []
        return (
            reps: record?.reps ?? best?.reps ?? 8,
            weight: record?.weight ?? best?.weight ?? weightOptions.first ?? 0
        )
    }

    /// Drops every in-progress draft so each set resolves fresh through `draftValues` —
    /// the record for set 1, the previous set's values thereafter. Only meaningful when
    /// moving to a different exercise; there's nothing to seed up front any more.
    private func clearDrafts() {
        draftReps.removeAll()
        draftWeight.removeAll()
        draftHoldSeconds.removeAll()
        draftBodyweight.removeAll()
    }

    /// Resolved rather than merely read: an untouched draft falls back to the carryover
    /// (or the record for set 1), so the displayed value never depends on whether some
    /// `.onAppear` has run yet.
    private func draftValues(entry: RepSectionExercise, exercise: Exercise, key: SetKey) -> (reps: Int, weight: Double, isBodyweight: Bool) {
        let carry = carryoverValues(for: entry, key: key)
        let seed = recordSeed(for: exercise, entry: entry)
        let fallbackReps = carry?.reps ?? seed.reps
        let fallbackWeight = carry?.weight ?? seed.weight
        // A carried-forward bodyweight set only stays bodyweight while the entry still
        // offers it.
        let fallbackBodyweight = entry.allowsBodyweight && (carry?.isBodyweight ?? false)
        return (
            reps: draftReps[key] ?? fallbackReps,
            weight: draftWeight[key] ?? fallbackWeight,
            isBodyweight: draftBodyweight[key] ?? fallbackBodyweight
        )
    }

    private func bindingReps(_ key: SetKey, entry: RepSectionExercise, exercise: Exercise) -> Binding<Int> {
        Binding(
            get: { draftValues(entry: entry, exercise: exercise, key: key).reps },
            set: { draftReps[key] = $0 }
        )
    }

    private func bindingWeight(_ key: SetKey, entry: RepSectionExercise, exercise: Exercise) -> Binding<Double> {
        Binding(
            get: { draftValues(entry: entry, exercise: exercise, key: key).weight },
            set: { draftWeight[key] = $0 }
        )
    }

    private func bindingBodyweight(_ key: SetKey, entry: RepSectionExercise, exercise: Exercise) -> Binding<Bool> {
        Binding(
            get: { draftValues(entry: entry, exercise: exercise, key: key).isBodyweight },
            set: { draftBodyweight[key] = $0 }
        )
    }

    private func bindingHoldSeconds(_ key: SetKey) -> Binding<Int> {
        Binding(get: { draftHoldSeconds[key] ?? 0 }, set: { draftHoldSeconds[key] = $0 })
    }

    // MARK: - Actions

    /// `values` is passed in when several sets are committed at once, so each is saved
    /// from a snapshot taken before any of them hit the store.
    private func logSet(
        entry: RepSectionExercise,
        key: SetKey,
        values: (reps: Int, weight: Double, isBodyweight: Bool)? = nil
    ) {
        restStartSignal += 1
        beginSaveLockout()
        // Resolved the same way the steppers display it, so logging a set the user
        // never touched saves exactly the value they were shown.
        let values = values ?? entry.exercise.map { draftValues(entry: entry, exercise: $0, key: key) }
        let reps = values?.reps ?? draftReps[key] ?? 8

        // The weight comes from whichever source this exercise is set to — typed number,
        // bodyweight zero, or the stepper's draft — so what's saved is what was shown.
        let resolved = entry.exercise.map { resolvedWeight(entry: entry, exercise: $0, key: key) }
        let isManual = entry.exercise.map { isManualEntry(for: entry, exercise: $0) } ?? false
        let weight = resolved?.weight ?? values?.weight ?? draftWeight[key] ?? 0
        let isBodyweight = resolved?.isBodyweight ?? values?.isBodyweight ?? false

        let log = SetLog(
            session: session,
            repSectionExercise: entry,
            exercise: entry.exercise,
            exerciseNameSnapshot: entry.exercise?.displayName,
            setIndex: key.index,
            reps: reps,
            weight: weight,
            weightUnit: entry.exercise.map { activeWeightUnit(for: entry, exercise: $0) } ?? AppSettings.weightUnit,
            isBodyweight: isBodyweight ? true : nil,
            side: key.side,
            repeatIndex: currentRepeat,
            equipment: isManual ? nil : entry.exercise.flatMap { chosenEquipment(for: entry, exercise: $0) },
            isManualWeight: isManual ? true : nil
        )
        context.insert(log)
        session.markDirty()
        try? context.save()
    }

    /// Commits both sides of one set together. Any side already logged for this index
    /// is skipped, so re-saving after cancelling just one side fills only the gap.
    private func logBothSides(entry: RepSectionExercise, index: Int) {
        let live = loggedSets(for: entry)
        let pending = SetSide.allCases
            .map { SetKey(index: index, side: $0) }
            .filter { loggedSet(for: entry, key: $0, in: live) == nil }

        // Both sides are resolved *before* either is written. Inserting one first would
        // otherwise let it feed back into the other's lookup, so the second side could
        // inherit the first's values instead of its own.
        let resolved: [(SetKey, (reps: Int, weight: Double, isBodyweight: Bool))] = pending.compactMap { key in
            guard let exercise = entry.exercise else { return nil }
            return (key, draftValues(entry: entry, exercise: exercise, key: key))
        }

        for (key, values) in resolved {
            logSet(entry: entry, key: key, values: values)
        }
    }

    private func logHoldSet(entry: RepSectionExercise, key: SetKey) {
        restStartSignal += 1
        beginSaveLockout()
        let holdSeconds = draftHoldSeconds[key] ?? 0
        let log = SetLog(
            session: session,
            repSectionExercise: entry,
            exercise: entry.exercise,
            exerciseNameSnapshot: entry.exercise?.displayName,
            setIndex: key.index,
            reps: 0,
            weight: 0,
            weightUnit: entry.exercise.map { activeWeightUnit(for: entry, exercise: $0) } ?? AppSettings.weightUnit,
            holdSeconds: holdSeconds,
            side: key.side,
            repeatIndex: currentRepeat
        )
        context.insert(log)
        session.markDirty()
        try? context.save()
    }

    /// Holds Save disabled for a second while the new set number is highlighted — long
    /// enough to see what changed, and it rules out a double-tap logging two sets.
    private func beginSaveLockout() {
        isSaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSaving = false
        }
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
