import SwiftUI
import SwiftData

struct RepSessionRunnerView: View {
    @Bindable var session: WorkoutSession
    let section: WorkoutSection
    let cues: TimerCueSettings
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
    /// Bumped the moment the forward nav button unlocks, to fire its one-shot pulse.
    @State private var nextPulseTrigger = 0
    /// Set the moment a set's stepper hits the bottom of the ladder with Bodyweight
    /// allowed — holds the entry so the confirmation dialog knows which one to switch
    /// (the same session-wide `select(.bodyweight, for:)` the equipment menu's own
    /// "Bodyweight" button already calls) if the user says yes.
    @State private var bodyweightOfferEntry: RepSectionExercise?

    /// What an exercise's weight is being loaded with for this session. Session-local
    /// rather than persisted: the workout's own `preferredEquipment` is the default,
    /// and this is the in-the-moment override.
    /// Deliberately only two cases. Typing a weight in is *not* a source — it's a way
    /// of entering a weight on the equipment you already chose, reached by tapping the
    /// value on a set row. A third "manual" source logged sets with no equipment at all,
    /// which filed their records under a null equipment the Records screen keys apart
    /// from the real one.
    enum WeightSource: Hashable {
        case equipment(UUID)
        /// No external load. Weight logs as 0 and the steppers give way to a plain
        /// "Bodyweight" readout.
        case bodyweight
    }

    @State private var weightSourceByEntry: [UUID: WeightSource] = [:]

    /// How an exercise is being performed this session — the execution-type counterpart
    /// to `WeightSource`, session-local for the same reason: the workout's own
    /// `executionType` is the default, and this is the in-the-moment override.
    ///
    /// An enum rather than a bare `UUID?` in the dictionary, because "chose none" and
    /// "hasn't chosen" have to stay distinguishable — a nested optional value would
    /// collapse them and make an explicit "None" fall back to the workout's setting.
    enum ExecutionChoice: Hashable {
        case none
        case type(UUID)
    }

    @State private var executionByEntry: [UUID: ExecutionChoice] = [:]

    /// Which rung of a progression this entry is being performed at — the id of the chosen
    /// exercise, session-local like the two overrides above.
    ///
    /// A plain id rather than an enum: unlike execution type there is no "none" to tell
    /// apart from "hasn't chosen", because a ladder always resolves to some exercise.
    @State private var levelByEntry: [UUID: UUID] = [:]
    /// Which exercise card has its record-history popover open, if any.
    @State private var historyPopoverEntryID: UUID?

    private var entries: [RepSectionExercise] { section.sortedRepExercises }
    private var currentIndex: Int { session.currentExerciseIndex ?? 0 }
    private var currentEntry: RepSectionExercise? {
        guard currentIndex >= 0, currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    var body: some View {
        // `resolvedExercise`, not `entry.exercise`: the progression menu can swap which
        // exercise this entry is being performed as, and everything below is built from
        // this one binding.
        if let entry = currentEntry, let exercise = resolvedExercise(for: entry) {
            VStack(spacing: 0) {
                // No insets: the band runs edge to edge like every other runner's
                // header, so its own fill is what meets the screen sides.
                header(exercise: exercise, entry: entry)
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
            .confirmationDialog(
                "There's nothing lighter to step down to. Switch to Bodyweight?",
                isPresented: Binding(
                    get: { bodyweightOfferEntry != nil },
                    set: { if !$0 { bodyweightOfferEntry = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Switch to Bodyweight") {
                    if let offerEntry = bodyweightOfferEntry {
                        select(.bodyweight, for: offerEntry)
                    }
                    bodyweightOfferEntry = nil
                }
                Button("Cancel", role: .cancel) { bodyweightOfferEntry = nil }
            }
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
                ExerciseVideoButton(exercise: exercise)
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
                    ExerciseVideoButton(exercise: exercise)
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

    /// The same full-width accent band the Follow Along / EMOM / AMRAP runners use, so
    /// every runner opens the same way. Two panels sit directly on the fill — separated
    /// by a white hairline, since a `Divider` is invisible against a solid color — rather
    /// than as cards floating on the page background.
    private func header(exercise: Exercise, entry: RepSectionExercise) -> some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                RestTimerView(
                    totalSeconds: entry.customRestSeconds ?? AppSettings.defaultRestSeconds,
                    cues: cues,
                    isSessionActive: session.status == .inProgress,
                    startSignal: $restStartSignal,
                    stopSignal: $restStopSignal,
                    onAccent: true,
                    height: headerHeight
                )
                // A third of the row, so the timer keeps the same proportion on any
                // width rather than a fixed square that crowds a small phone.
                .frame(width: geometry.size.width * 0.33)

                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    // Which part of the workout you're in, set apart from the exercise
                    // details below it.
                    Text(sectionBannerText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(headingTitle(entry: entry, exercise: exercise))
                            .font(nameFont(bandHeight: geometry.size.height))
                            // No guard at all before this: a long name simply spilled
                            // out of the band. Two lines is what the taller iPad band
                            // has room for, and the scale factor catches the rest.
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white)
                        if !exercise.equipmentItems.isEmpty {
                            Label(exercise.equipmentItems.map(\.name).joined(separator: ", "), systemImage: "dumbbell.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        if !exercise.muscles.isEmpty {
                            Text(exercise.muscles.map(\.name).sorted().joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: headerHeight)
        .background(Color.appAccent)
    }

    /// Taller on iPad, where the phone's 132pt band left the exercise name at phone size
    /// on a screen with room to spare — but only halfway there: a 200pt band made the
    /// name the loudest thing on the screen and ate into the columns below it. The rest
    /// timer beside it is sized from this too, so the two panels stay the same height.
    private var headerHeight: CGFloat {
        horizontalSizeClass == .regular ? 166 : RestTimerView.defaultHeight
    }

    /// Scaled off the band it sits in on iPad — the same geometry-derived sizing the
    /// other runners give their hero timers — and left at the phone's text style on
    /// compact width, so that layout is untouched.
    private func nameFont(bandHeight: CGFloat) -> Font {
        guard horizontalSizeClass == .regular else { return .appSerif(.title3) }
        return .appSerif(size: bandHeight * 0.22)
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
            // Both modes: a max-time hold can be loaded too, and the same
            // "locked once a set is logged" rule applies to either.
            equipmentLine(entry: entry, exercise: exercise)
            executionLine(entry: entry, exercise: exercise)
            progressionLine(entry: entry, exercise: exercise)
            recordLine(entry: entry, exercise: exercise)

            Divider()

            setsSection(entry: entry, exercise: exercise)

            addTypedWeightsRow(entry: entry, exercise: exercise)

            Divider()

            SessionNoteRow(session: session, exercise: exercise)
                .id(exercise.id)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        // A child whose minimum exceeds the proposal makes `.padding` overrun rather
        // than clamp, and a leading-aligned parent dumps all of that overflow on the
        // right — which put this card's trailing edge off screen. Clipping guarantees
        // the card never paints wider than the width it was handed, whatever a row
        // inside it asks for at large type sizes.
        .clipped()
        .cardStyle()
    }

    /// Equipment name with a glass pencil menu — the same treatment "New Section" uses.
    /// Not locked by a logged set — see `canOpenEquipmentMenu` — only by Equipment
    /// Editable, which Bodyweight on its own stays exempt from.
    private func equipmentLine(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let canEdit = canOpenEquipmentMenu(for: entry, exercise: exercise)
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
                            // Locked out individually when Editable is off, except the
                            // one equipment already fixed as this entry's own default —
                            // reselecting it is how "back from Bodyweight" works
                            // without opening up the full list.
                            .disabled(!entry.equipmentEditable && item.id != fixedDefaultEquipmentID(for: entry, exercise: exercise))
                    }
                    if allowsBodyweightSource(for: entry, exercise: exercise) {
                        Button("Bodyweight") { select(.bodyweight, for: entry) }
                    }
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

    /// How the exercise is being performed, with the same glass pencil menu the
    /// equipment line uses — not locked by a logged set for the same reason
    /// (`canChangeExecutionType`), but its own independent Editable flag, unrelated to
    /// equipment's own: a builder can fix equipment and leave execution type open, or
    /// the other way around.
    ///
    /// Hidden entirely for an exercise carrying no types: unlike equipment, there is no
    /// implicit fallback worth naming when the catalog offers nothing. Also hidden —
    /// rather than shown with a dead pencil — when nothing is selected and Editable is
    /// off: there's neither a value worth naming nor anything the row could ever do.
    @ViewBuilder
    private func executionLine(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let options = exercise.sortedExecutionTypes
        if !options.isEmpty, !(entry.executionType == nil && !entry.executionTypeEditable) {
            let canEdit = canChangeExecutionType(for: entry)
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
                Text(executionLabel(for: entry, exercise: exercise))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                GlassEffectContainer {
                    Menu {
                        ForEach(options) { type in
                            Button(type.name) { select(.type(type.id), for: entry) }
                        }
                        Button("None") { select(.none, for: entry) }
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
    }

    /// Which rung of the progression is being performed, with the same glass pencil menu
    /// the equipment and execution lines use.
    ///
    /// **Deliberately not locked once a set is logged**, unlike those two. They lock
    /// because the sets already recorded belong to what was chosen; a progression swap is
    /// the opposite case — logging sets 1 and 2 at one rung and set 3 at the next *is*
    /// levelling up, and it is the reason the control exists.
    @ViewBuilder
    private func progressionLine(entry: RepSectionExercise, exercise: Exercise) -> some View {
        if let group = progressionGroup(for: entry, exercise: exercise) {
            HStack(spacing: 8) {
                Image(systemName: "figure.stairs")
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
                Text(progressionLabel(exercise: exercise, group: group))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                GlassEffectContainer {
                    Menu {
                        ForEach(group.sortedSteps) { step in
                            if let rung = step.exercise {
                                Button("Level \(step.level) · \(rung.displayName)") {
                                    selectProgression(rung.id, for: entry)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Progression Level 3 of 5" — the rung's *name* is already the card's heading, so
    /// repeating it here would say the same thing twice in adjacent lines.
    private func progressionLabel(exercise: Exercise, group: ProgressionGroup) -> String {
        "Progression Level \(exercise.progressionLevel ?? 1) of \(group.maxLevel)"
    }

    /// The record for the equipment in use, with "last" appended only when there is one.
    @ViewBuilder
    private func recordLine(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let equipment = chosenEquipment(for: entry, exercise: exercise)
        let executionType = recordExecutionType(for: entry, exercise: exercise)
        // Looked up by the shape this entry tracks: a max-time record and a weight/reps
        // record for the same equipment are different records, and reading either as the
        // other used to overwrite it.
        let record = PersonalRecordQueries.current(
            for: exercise,
            equipment: equipment,
            executionType: executionType,
            trackingMode: entry.trackingMode,
            isBodyweight: isBodyweightSource(for: entry, exercise: exercise),
            context: context
        )

        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            Text(recordSummary(entry: entry, exercise: exercise, equipment: equipment, executionType: executionType, record: record))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Only when there's something to show: a record that has never been beaten has
            // no progression, and an always-present button that usually does nothing is worse
            // than no button.
            if let record, !record.history.isEmpty {
                Button {
                    historyPopoverEntryID = entry.id
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: historyBinding(for: entry.id)) {
                    recordHistoryPopover(record)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same reason `.popover(item:)` isn't used in `SectionCardView`: it would try to
    /// present on every exercise card on screen, so the open one is tracked by id.
    private func historyBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { historyPopoverEntryID == id },
            set: { if !$0 && historyPopoverEntryID == id { historyPopoverEntryID = nil } }
        )
    }

    /// The record's progression, newest first — the standing record on top, then every
    /// value it superseded. Read-only: mid-workout is the wrong moment to prune history,
    /// so deleting an entry stays on the Records tab.
    private func recordHistoryPopover(_ record: PersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record progression")
                .font(.headline)
                .foregroundStyle(Color.appInk)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // A record carries no achievement date of its own, so `updatedAt` is
                    // the best stamp available — the same one `setRecord` files the values
                    // it supersedes under.
                    historyPopoverRow(
                        text: PersonalRecordFormatting.summary(record),
                        date: record.updatedAt,
                        isCurrent: true
                    )
                    // `history` already drops tombstones and sorts newest first.
                    ForEach(record.history) { entry in
                        historyPopoverRow(
                            text: PersonalRecordFormatting.summary(entry),
                            date: entry.achievedAt,
                            isCurrent: false
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 260, height: 280)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }

    private func historyPopoverRow(text: String, date: Date, isCurrent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.appInk)
            Spacer(minLength: 8)
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func recordSummary(
        entry: RepSectionExercise,
        exercise: Exercise,
        equipment: Equipment?,
        executionType: ExecutionType?,
        record: PersonalRecord?
    ) -> String {
        // The derived fallbacks are scoped to match the record they stand in for —
        // otherwise an exercise splitting by type would show one type's record above
        // another type's history the moment the record was missing.
        let splits = exercise.splitsRecordsByExecutionType
        switch entry.trackingMode {
        case .repsWeight:
            let last = SetLogQueries.lastBestSet(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, excluding: session, context: context)
            // Weight (or Bodyweight) leads, reps trails named as "reps" — the same
            // format `PersonalRecordFormatting.summary` uses for `record` below, so
            // "record" and "last" never disagree on how to say the same thing. Formatted
            // against `equipment` — the specific piece this record/best/last all share,
            // already resolved by the caller — not re-derived from the exercise, which
            // is what let "last" show a different unit than "record" for an exercise
            // carrying equipment in more than one.
            let lastSuffix = last.map { " · last \(formattedWeight($0.weight, equipment: equipment, exercise: exercise)) × \($0.reps) reps" } ?? ""
            // Through the shared formatter when a record exists, rather than reading
            // `record.weight` directly here: `setRecord` always nils it for a bodyweight
            // record, and coalescing that back to a fake `0` is what used to render
            // "8 × 0 kg" instead of naming Bodyweight. `bestSetEver`'s own fallback needs
            // no such check — its query already excludes bodyweight sets entirely.
            if let record {
                return PersonalRecordFormatting.summary(record) + lastSuffix
            }
            guard let best = SetLogQueries.bestSetEver(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, context: context) else {
                return "No record set yet"
            }
            return "\(formattedWeight(best.weight, equipment: equipment, exercise: exercise)) × \(best.reps) reps" + lastSuffix
        case .maxHoldTime:
            // `record` is already resolved for this equipment by the caller, and the
            // history fallbacks are scoped to match — a loaded hold is its own record.
            let bestHold = record?.holdSeconds ?? SetLogQueries.bestHoldEver(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, context: context)
            let lastHold = SetLogQueries.lastHoldSeconds(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, excluding: session, context: context)
            guard let bestHold else { return "No record set yet" }
            var text = "\(bestHold)s"
            if let lastHold { text += " · last \(lastHold)s" }
            return text
        }
    }


    private func select(_ source: WeightSource, for entry: RepSectionExercise) {
        weightSourceByEntry[entry.id] = source
        clearDrafts()
    }

    /// Drafts are cleared alongside the choice for the same reason equipment does it: with
    /// records split by type, set 1 seeds from the chosen type's record, and keeping the
    /// old draft would show the previous type's numbers under the new one's name.
    private func select(_ choice: ExecutionChoice, for entry: RepSectionExercise) {
        executionByEntry[entry.id] = choice
        clearDrafts()
    }

    /// Clearing drafts matters most here. This is the one choice that can change *after*
    /// sets are logged, and `carryoverValues` seeds each set from the previous one within
    /// the entry — without this, set 3 on the harder rung would open at set 2's reps and
    /// weight from the easier one.
    private func selectProgression(_ exerciseID: UUID, for entry: RepSectionExercise) {
        levelByEntry[entry.id] = exerciseID
        // The equipment choice belonged to the *previous* rung. Rungs rarely share
        // equipment, and a stale id resolves to nil in `chosenEquipment` while
        // `weightSource` still reports `.equipment` — which logs a real weight against no
        // equipment at all, the shape that files a phantom record.
        weightSourceByEntry[entry.id] = nil
        clearDrafts()
    }

    @ViewBuilder
    private func setsSection(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let weightOptions = activeWeightOptions(for: entry, exercise: exercise)
        let logs = loggedSets(for: entry)
        let splits = exercise.splitsRecordsByExecutionType
        let executionType = recordExecutionType(for: entry, exercise: exercise)
        let last = SetLogQueries.lastBestSet(exercise: exercise, executionType: executionType, scopesByExecutionType: splits, excluding: session, context: context)
        let bestHold = entry.trackingMode == .maxHoldTime
            ? (PersonalRecordQueries.current(
                    for: exercise,
                    equipment: chosenEquipment(for: entry, exercise: exercise),
                    executionType: executionType,
                    trackingMode: .maxHoldTime,
                    isBodyweight: isBodyweightSource(for: entry, exercise: exercise),
                    context: context
               )?.holdSeconds
                ?? SetLogQueries.bestHoldEver(exercise: exercise, equipment: chosenEquipment(for: entry, exercise: exercise), executionType: executionType, scopesByExecutionType: splits, context: context))
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
                                exerciseName: headingTitle(entry: entry, exercise: exercise),
                                headStartSeconds: entry.headStartSeconds,
                                previousBest: bestHold,
                                recordedSeconds: .constant(log.holdSeconds ?? 0),
                                // Read back off the log, not the live source: a saved set
                                // is a record of what it was actually performed with.
                                weightMode: log.isBodyweight == true ? .bodyweight : .stepper,
                                weightUnit: log.weightUnit,
                                weight: .constant(log.weight),
                                isBodyweight: .constant(log.isBodyweight == true),
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

    /// Offers to put this pass's typed weights on the equipment's ladder, so next time
    /// they can be stepped to instead of typed again.
    ///
    /// One row for the pass rather than one under each set: in the ordinary case of a
    /// single odd weight they look the same, and it avoids repeating the identical offer
    /// under every set that shares it.
    @ViewBuilder
    private func addTypedWeightsRow(entry: RepSectionExercise, exercise: Exercise) -> some View {
        let missing = typedWeightsMissingFromEquipment(entry: entry, exercise: exercise)
        if let equipment = chosenEquipment(for: entry, exercise: exercise), !missing.isEmpty {
            Button {
                addWeightsToEquipment(missing, equipment: equipment)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Add \(missing.map { formattedWeightValue($0, unit: equipment.effectiveWeightUnit) }.joined(separator: ", ")) to \(equipment.name)")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
        }
    }

    /// Distinct weights logged in this pass that the equipment has no preset for. Empty
    /// for bodyweight, and for equipment with no ladder at all — there is nothing to add
    /// to, and every weight would qualify.
    private func typedWeightsMissingFromEquipment(entry: RepSectionExercise, exercise: Exercise) -> [Double] {
        let options = activeWeightOptions(for: entry, exercise: exercise)
        guard !options.isEmpty else { return [] }
        // Holds are included: a weighted plank is loaded on the same equipment and its
        // weight is just as absent from the ladder. Bodyweight sets aren't loaded at all.
        var seen: [Double] = []
        for log in loggedSets(for: entry) where log.isBodyweight != true {
            let weight = log.weight
            guard !options.contains(where: { abs($0.value - weight) < 0.0001 }) else { continue }
            guard !seen.contains(where: { abs($0 - weight) < 0.0001 }) else { continue }
            seen.append(weight)
        }
        return seen.sorted()
    }

    /// Where each weight lands in the ladder comes from its value, not from `sortOrder`
    /// (see `Equipment.sortedWeightCombos`) — so 5 kg added to a 20/25/30 barbell sits
    /// first rather than after 30. `sortOrder` is still assigned to keep the stored row
    /// coherent for the archive round-trip.
    private func addWeightsToEquipment(_ weights: [Double], equipment: Equipment) {
        var nextOrder = (equipment.weightCombos.map(\.sortOrder).max() ?? -1) + 1
        for weight in weights {
            // `typedWeightsMissingFromEquipment` already filters these, so this is only
            // belt-and-braces — a duplicate preset makes the ± stepper look stuck.
            guard !equipment.sortedWeightCombos.contains(where: { abs($0.value - weight) < 0.0001 }) else { continue }
            context.insert(WeightCombo(equipment: equipment, value: weight, sortOrder: nextOrder))
            nextOrder += 1
        }
        equipment.markDirty()
        try? context.save()
    }

    /// A weight the equipment doesn't have yet, named the way it will read once added —
    /// an option by number, anything else as "value unit". `Equipment.optionUnit` is a
    /// storage token, so printing it here offered to "Add 7 level".
    private func formattedWeightValue(_ value: Double, unit: String) -> String {
        if unit == Equipment.optionUnit { return WeightCombo.optionDisplayName(for: value) }
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
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
                        Text(loggedSetSummary(log))
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

    /// Formatted against the log's own stamped `equipment`/`weightUnit`, not
    /// `exercise.weightedEquipment` — a set already logged keeps the unit it was
    /// actually recorded in, which can differ from whatever the exercise's generic
    /// equipment resolves to today for an exercise carrying more than one.
    private func loggedSetSummary(_ log: SetLog) -> String {
        if log.isBodyweight == true { return "Bodyweight × \(log.reps)" }
        let weightText: String
        if let equipment = log.equipment, equipment.usesOptions {
            weightText = WeightCombo.optionDisplayName(for: log.weight, in: equipment.sortedWeightCombos)
        } else {
            weightText = formattedSetWeight(log.weight, unit: log.weightUnit)
        }
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
                                    allowsBodyweight: allowsBodyweightSource(for: entry, exercise: exercise),
                                    showsSaveButton: false,
                                    isSaving: isSaving,
                                    onOfferBodyweight: { bodyweightOfferEntry = entry },
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
                        allowsBodyweight: allowsBodyweightSource(for: entry, exercise: exercise),
                        isSaving: isSaving,
                        onOfferBodyweight: { bodyweightOfferEntry = entry },
                        onLog: { logSet(entry: entry, key: key) },
                        onCancel: {}
                    )
                }
            case .maxHoldTime:
                HoldSetRowView(
                    setNumber: key.index + 1,
                    exerciseName: headingTitle(entry: entry, exercise: exercise),
                    headStartSeconds: entry.headStartSeconds,
                    previousBest: bestHold,
                    recordedSeconds: bindingHoldSeconds(key),
                    weightMode: weightMode(for: entry, exercise: exercise),
                    weightOptions: weightOptions,
                    weightUnit: activeWeightUnit(for: entry, exercise: exercise),
                    weight: bindingWeight(key, entry: entry, exercise: exercise),
                    isBodyweight: bindingBodyweight(key, entry: entry, exercise: exercise),
                    allowsBodyweight: allowsBodyweightSource(for: entry, exercise: exercise),
                    onOfferBodyweight: { bodyweightOfferEntry = entry },
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
                    nextButton(entry: entry, width: quarterWidth)
                } else {
                    // No Spacers — Previous/Next/Skip widths are sized to exactly fill
                    // the row themselves, Skip always half a side button's width.
                    let remaining = geometry.size.width - spacing * 2
                    let sideWidth = remaining / 2.5
                    navButton(.previous, entry: entry, width: sideWidth)
                    skipButton(entry: entry, width: sideWidth * 0.5, isEnabled: isSkipEnabled)
                    nextButton(entry: entry, width: sideWidth)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // Only on the false→true edge: coming back to an exercise, or advancing away
        // from a finished one, flips this the other way and shouldn't pulse.
        .onChange(of: canAdvance(entry)) { _, isEnabled in
            if isEnabled { nextPulseTrigger += 1 }
        }
        .frame(height: Self.navBarHeight)
        .padding(.horizontal)
        .padding(.top)
        // No bottom pad — the safe-area inset below already separates the bar from the
        // screen edge, so anything here is pure added height.
        .padding(.bottom, 0)
        .background(Color.appSurface)
    }

    /// The forward button plus its unlock pulse. The animator lives out here rather than
    /// inside `navButton` because `navButton` swaps between two style branches at the
    /// exact moment the pulse should run — a keyframe animator attached inside would be
    /// inserted fresh on that swap and start already at rest. Applied here its identity
    /// is stable across the swap, so the trigger actually animates it.
    private func nextButton(entry: RepSectionExercise, width: CGFloat) -> some View {
        navButton(.next, entry: entry, width: width)
            // Grows and settles the moment the last set lands, so the way forward
            // opening is something you feel rather than have to notice.
            .keyframeAnimator(initialValue: 1.0, trigger: nextPulseTrigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.10, duration: 0.18, spring: .snappy)
                SpringKeyframe(1.00, duration: 0.30, spring: .bouncy)
            }
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
        // `.bordered`, not `.borderedProminent` — the same translucent weight Previous
        // carries, just in red. A solid red fill made skipping look like the loudest
        // thing on the bar; this leaves the prominent fill for the forward button.
        .buttonStyle(.bordered)
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
    @ViewBuilder
    private func navButton(_ direction: NavDirection, entry: RepSectionExercise, width: CGFloat) -> some View {
        let isPrevious = direction == .previous
        let isDisabled = isPrevious ? currentIndex == 0 : !canAdvance(entry)
        // Forward and unlocked — every set logged, so this is the one button on the bar
        // worth pressing. It's the only one that earns a prominent fill.
        let isForwardActive = !isPrevious && !isDisabled

        let content = navButtonContent(isPrevious: isPrevious)
        let action = { if isPrevious { goToPrevious() } else { goToNext(entry: entry) } }
        let label = navButtonLabel(title: content.title, subtitle: content.subtitle,
                                   icon: content.icon, isPrevious: isPrevious,
                                   isProminent: isForwardActive)

        // Two branches rather than one chain because `buttonStyle` can't be applied
        // conditionally — everything after it is identical.
        if isForwardActive {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .buttonBorderShape(.roundedRectangle(radius: Self.navBarCornerRadius))
                .controlSize(.large)
                .frame(width: width, height: Self.navBarHeight)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: Self.navBarCornerRadius))
                .controlSize(.large)
                .frame(width: width, height: Self.navBarHeight)
                .disabled(isDisabled)
        }
    }

    /// What the button says and points at. Lives outside `navButton` because that one is
    /// a `@ViewBuilder`, which would read this if/else chain as a view branch rather than
    /// as deferred assignment.
    private func navButtonContent(isPrevious: Bool) -> (title: String, subtitle: String?, icon: String) {
        if isPrevious {
            return ("Previous", previousExerciseName, "chevron.left")
        } else if !isLastExerciseInSection {
            return ("Next", nextExerciseName, "chevron.right")
        } else if !isLastSection {
            return ("Next Section", nextSectionName, "chevron.right")
        } else {
            return ("Finish", nil, "checkmark")
        }
    }

    /// The shared label for every nav button. `isProminent` is what the forward button
    /// passes once it's filled with accent green: `.secondary` renders as dark gray,
    /// which all but disappears against that fill, so the subtitle switches to white.
    private func navButtonLabel(title: String, subtitle: String?, icon: String,
                                isPrevious: Bool, isProminent: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if isPrevious { Image(systemName: icon) }
                Text(title)
                if !isPrevious { Image(systemName: icon) }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isProminent ? AnyShapeStyle(Color.white.opacity(0.85))
                                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .lineLimit(1)
            }
        }
        // maxHeight: .infinity (not just maxWidth) is what actually centers a
        // single-line label within the button's full fixed height — without it the
        // VStack only fills width, keeping its natural (short) height and just
        // sitting near the top of the taller button instead of centering.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previousExerciseName: String? {
        guard currentIndex > 0 else { return nil }
        return neighbourTitle(entries[currentIndex - 1])
    }

    private var nextExerciseName: String? {
        let next = currentIndex + 1
        guard next < entries.count else { return nil }
        return neighbourTitle(entries[next])
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
        if entry.prefersBodyweight { return .bodyweight }
        if let preferred = entry.preferredEquipment { return .equipment(preferred.id) }
        // The catalog's own resolution, not the alphabetically first item — otherwise
        // the runner silently disagrees with the default shown in the builder. Reads
        // `defaultWeightedEquipment`, so an exercise that means bodyweight by default
        // starts unloaded rather than on whichever weight happens to be attached.
        if let resolved = exercise.defaultWeightedEquipment { return .equipment(resolved.id) }
        return .bodyweight
    }

    private func chosenEquipment(for entry: RepSectionExercise, exercise: Exercise) -> Equipment? {
        guard case .equipment(let id) = weightSource(for: entry, exercise: exercise) else { return nil }
        // Falling back rather than returning nil. `weightSource` resolves an id from three
        // places that aren't validated against this list — a stale `preferredEquipment`,
        // an equipment since un-flagged as weighted, one detached from the exercise — and
        // a nil here while the source still says `.equipment` logs a real weight under no
        // equipment, which the Records screen keys apart as its own phantom record.
        let options = weightedOptions(for: exercise)
        return options.first { $0.id == id } ?? options.first
    }

    /// True when nothing is loaded — the sets show "Bodyweight" instead of a stepper.
    private func isBodyweightSource(for entry: RepSectionExercise, exercise: Exercise) -> Bool {
        weightSource(for: entry, exercise: exercise) == .bodyweight
    }

    /// Whether bodyweight is a legitimate choice for this exercise: the catalog has to
    /// allow it (or offer no weighted equipment at all) *and* this entry's own
    /// Bodyweight on/off toggle has to be on — the builder's row that actually exposes
    /// the choice. Unaffected by `equipmentEditable`: switching to Bodyweight from the
    /// stepper's own bottom-of-ladder prompt is deliberately exempt from that lock.
    private func allowsBodyweightSource(for entry: RepSectionExercise, exercise: Exercise) -> Bool {
        entry.allowsBodyweight && exercise.allowsBodyweightSource
    }

    /// How each set's weight control should render, given the exercise's source.
    private func weightMode(for entry: RepSectionExercise, exercise: Exercise) -> SetRowView.WeightMode {
        switch weightSource(for: entry, exercise: exercise) {
        case .bodyweight: return .bodyweight
        case .equipment: return .stepper
        }
    }

    /// The weight a set would log right now — zero for bodyweight, otherwise the
    /// draft the stepper and the wheel both edit.
    private func resolvedWeight(entry: RepSectionExercise, exercise: Exercise, key: SetKey) -> (weight: Double, isBodyweight: Bool) {
        switch weightSource(for: entry, exercise: exercise) {
        case .bodyweight:
            return (0, true)
        case .equipment:
            let values = draftValues(entry: entry, exercise: exercise, key: key)
            return (values.isBodyweight ? 0 : values.weight, values.isBodyweight)
        }
    }

    /// The equipment this entry resolves to with no session override in play — the
    /// fixed point Equipment Editable off pins the runner to, and the "go back" target
    /// once Bodyweight (independently allowed regardless of Editable) has been picked
    /// instead.
    private func fixedDefaultEquipmentID(for entry: RepSectionExercise, exercise: Exercise) -> UUID? {
        if entry.prefersBodyweight { return nil }
        if let preferred = entry.preferredEquipment { return preferred.id }
        return exercise.defaultWeightedEquipment?.id
    }

    /// Whether the equipment menu opens at all. Not locked by a logged set the way it
    /// once was — a set already logged keeps its own recorded equipment regardless of
    /// what this changes to (baked into the `SetLog` at the moment it was logged, the
    /// same way `progressionLine` was already never locked by one either — see its own
    /// note), so changing course only ever affects sets still to come: the choice
    /// carries forward as the default for the next set, editable again for it and every
    /// set after, same as it would be for the very first. Open as long as either full
    /// editing is allowed or Bodyweight is — the exemption "Equipment Editable off,
    /// Bodyweight on" needs, since without it the whole menu, including the
    /// always-legal Bodyweight choice, would go inert together.
    private func canOpenEquipmentMenu(for entry: RepSectionExercise, exercise: Exercise) -> Bool {
        entry.equipmentEditable || allowsBodyweightSource(for: entry, exercise: exercise)
    }

    /// The execution-type counterpart to `canOpenEquipmentMenu` — not locked by a
    /// logged set for the same reason, and against `executionTypeEditable` instead of
    /// `equipmentEditable`, since the two fields lock independently.
    private func canChangeExecutionType(for entry: RepSectionExercise) -> Bool {
        entry.executionTypeEditable
    }

    /// What the entry either side of this one will be called when you reach it.
    ///
    /// Through `resolvedExercise` rather than `displayTitle`, so a neighbour on a ladder
    /// names the rung it will actually open at. Its session override is unset by
    /// definition — you haven't been there yet — so this resolves to the reached level.
    private func neighbourTitle(_ entry: RepSectionExercise) -> String {
        ExerciseNaming.title(resolvedExercise(for: entry), executionType: entry.executionType)
    }

    // MARK: - Progression choice

    /// The exercise this entry is actually being performed as.
    ///
    /// **Every read of `entry.exercise` during a run must come through here**, or the
    /// screen shows one exercise while the log records another. `body` binds this once and
    /// passes it down, which covers the card; the logging paths resolve it themselves.
    private func resolvedExercise(for entry: RepSectionExercise) -> Exercise? {
        guard let planned = entry.exercise else { return nil }
        // The entry opted out: run exactly what the workout says. Checked here and not
        // only in `progressionLine`, or the substitution would still happen silently with
        // no control on screen to explain it.
        guard entry.progressionEnabled else { return planned }
        guard let group = planned.progressionGroup else { return planned }

        // The session's own choice wins outright — it is the whole point of the menu.
        if let chosenID = levelByEntry[entry.id],
           let chosen = group.sortedSteps.first(where: { $0.exercise?.id == chosenID })?.exercise {
            return chosen
        }

        // Otherwise open at the level actually reached, but never *below* what the workout
        // asked for: building a session around the easy rung on purpose is a legitimate
        // thing to do, and reaching level 4 shouldn't silently rewrite it.
        let plannedLevel = planned.progressionLevel ?? 1
        guard group.reachedLevel > plannedLevel else { return planned }

        // Several exercises can share a level, so there may be no single answer. The
        // planned exercise wins if it is one of them; otherwise take the first, which
        // `sortedSteps` orders by name so it can't shuffle between renders.
        let candidates = group.steps(atLevel: group.reachedLevel)
        return candidates.first(where: { $0.exercise?.id == planned.id })?.exercise
            ?? candidates.first?.exercise
            ?? planned
    }

    /// The ladder to offer, if this entry is on one worth offering.
    private func progressionGroup(for entry: RepSectionExercise, exercise: Exercise) -> ProgressionGroup? {
        guard entry.progressionEnabled else { return nil }
        guard let group = exercise.progressionGroup, group.sortedSteps.count > 1 else { return nil }
        return group
    }

    /// Raises the ladder's reached level to whatever was just performed.
    ///
    /// Never lowers it. Dropping to an easier rung for a session is not losing a level —
    /// the same one-way rule a personal record follows, which is what makes the next
    /// workout open where you actually got to.
    private func raiseReachedLevel(performing exercise: Exercise) {
        guard let group = exercise.progressionGroup,
              let level = exercise.progressionLevel,
              level > group.reachedLevel
        else { return }
        group.reachedLevel = level
        group.markDirty()
        try? context.save()
    }

    // MARK: - Execution type choice

    /// The session's choice, falling back to the workout's, then to no type at all.
    private func executionChoice(for entry: RepSectionExercise, exercise: Exercise) -> ExecutionChoice {
        if let chosen = executionByEntry[entry.id] { return chosen }
        if let preferred = entry.executionType { return .type(preferred.id) }
        return .none
    }

    /// What the set being logged right now was performed as. Resolved against the
    /// exercise's live list, so a type detached from the catalog mid-workout reads as
    /// none rather than as a stale name.
    private func chosenExecutionType(for entry: RepSectionExercise, exercise: Exercise) -> ExecutionType? {
        guard case .type(let id) = executionChoice(for: entry, exercise: exercise) else { return nil }
        return exercise.sortedExecutionTypes.first { $0.id == id }
    }

    /// The type a record lookup should be scoped to — nil unless this exercise actually
    /// splits its records, which is the whole of the "separate records per type" rule.
    private func recordExecutionType(for entry: RepSectionExercise, exercise: Exercise) -> ExecutionType? {
        PersonalRecordQueries.resolvedExecutionType(
            chosenExecutionType(for: entry, exercise: exercise),
            for: exercise
        )
    }

    /// The exercise's name with the execution type folded in, for every heading this
    /// runner shows.
    ///
    /// Built from `chosenExecutionType` rather than `entry.displayTitle`, because this is
    /// the one place the type can be changed mid-workout: the heading has to name what the
    /// next set will actually be logged as, not what the workout was built with.
    private func headingTitle(entry: RepSectionExercise, exercise: Exercise) -> String {
        ExerciseNaming.title(exercise, executionType: chosenExecutionType(for: entry, exercise: exercise))
    }

    private func executionLabel(for entry: RepSectionExercise, exercise: Exercise) -> String {
        chosenExecutionType(for: entry, exercise: exercise)?.name ?? "No execution type"
    }

    private func equipmentLabel(for entry: RepSectionExercise, exercise: Exercise) -> String {
        switch weightSource(for: entry, exercise: exercise) {
        case .bodyweight: return "Bodyweight"
        case .equipment: return chosenEquipment(for: entry, exercise: exercise)?.name ?? "Bodyweight"
        }
    }

    /// The unit that a set logged right now would carry.
    private func activeWeightUnit(for entry: RepSectionExercise, exercise: Exercise) -> String {
        chosenEquipment(for: entry, exercise: exercise)?.effectiveWeightUnit ?? AppSettings.weightUnit
    }

    /// Whether a logged weight was typed rather than picked off the equipment's ladder.
    /// Derived rather than tracked as a mode: a weight that matches no preset is by
    /// definition one that was entered by hand, which is exactly what `SetLog`'s own
    /// `isManualWeight` documents. `nil` when there are no presets to deviate from.
    ///
    /// Compared with a tolerance — these are `Double`s that have been through a wheel
    /// and a stepper, and exact equality would flag a matching weight as manual.
    private func manualWeightFlag(weight: Double, options: [WeightCombo]) -> Bool? {
        guard !options.isEmpty else { return nil }
        let matchesPreset = options.contains { abs($0.value - weight) < 0.0001 }
        return matchesPreset ? nil : true
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
    ///  2. the nearest logged set before it, *if* it was logged under the same
    ///     exercise/equipment/execution type this set currently resolves to — each set
    ///     starts where the last one landed, so a heavier or lighter working set
    ///     carries forward instead of snapping back to the all-time record. But once
    ///     any of those three changes for this set — editing equipment, execution
    ///     type, or progression level is no longer locked out after the first set logs
    ///     — the earlier set's numbers belong to a different combination entirely, so
    ///     carrying them forward would keep showing the old combination's last value
    ///     instead of the new one's own record;
    ///  3. `nil`, leaving `recordSeed` to supply the value (set 1's usual case, and now
    ///     also whichever later set first changes what it's loaded with).
    ///
    /// Reads `session.setLogs` directly rather than `SetLogQueries` — those exclude the
    /// current session by design, so they can't see the sets just logged.
    ///
    /// With sides tracked, each side carries its own thread: the right leg's set 2 seeds
    /// from the right leg's set 1, falling back to the other side only when this one has
    /// no history yet (so set 1 Right still starts from set 1 Left rather than the
    /// all-time record).
    private func carryoverValues(for entry: RepSectionExercise, exercise: Exercise, key: SetKey) -> (reps: Int, weight: Double, isBodyweight: Bool)? {
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
        let currentEquipmentID = chosenEquipment(for: entry, exercise: exercise)?.id
        let currentExecutionTypeID = recordExecutionType(for: entry, exercise: exercise)?.id

        if let previousSameSide = live
            .filter({ $0.side == key.side && $0.setIndex < key.index })
            .max(by: { $0.setIndex < $1.setIndex }),
           previousSameSide.exercise?.id == exercise.id,
           previousSameSide.equipment?.id == currentEquipmentID,
           previousSameSide.executionType?.id == currentExecutionTypeID {
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

    /// `equipment` should be the specific one this value was actually measured on, when
    /// it's known — falling back to `exercise.weightedEquipment` re-derives *an*
    /// equipment for the exercise, not necessarily the one in play, which is what let
    /// "last" disagree with "record" on unit for an exercise carrying equipment in more
    /// than one unit.
    private func formattedWeight(_ value: Double, equipment: Equipment? = nil, exercise: Exercise) -> String {
        guard let equipment = equipment ?? exercise.weightedEquipment else {
            let unit = AppSettings.weightUnit
            return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
        }
        if equipment.usesOptions {
            return WeightCombo.optionDisplayName(for: value, in: equipment.sortedWeightCombos)
        }
        let unit = equipment.effectiveWeightUnit
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(unit)" : "\(value) \(unit)"
    }

    /// The starting point for an exercise's first set: the personal record, then the
    /// best set from the last time this exercise was trained, then the entry's own
    /// configured starting point (`RepSectionExercise.startingWeight`/`startingReps`,
    /// set in the exercise's settings panel — nil unless the workout's builder actually
    /// set one), then the lightest weight the equipment offers.
    private func recordSeed(for exercise: Exercise, entry: RepSectionExercise? = nil) -> (reps: Int, weight: Double) {
        // Seeded from the same equipment the set will be logged on, so switching
        // equipment re-seeds from that equipment's own history.
        let equipment = entry.flatMap { chosenEquipment(for: $0, exercise: exercise) }
        // And from the same execution type, for the same reason — switching type re-seeds
        // from that type's own history once the exercise keeps records apart.
        let executionType = entry.flatMap { recordExecutionType(for: $0, exercise: exercise) }
        let splits = exercise.splitsRecordsByExecutionType
        // Reps and weight, so only the weight/reps record has anything to seed from.
        let record = PersonalRecordQueries.current(
            for: exercise,
            equipment: equipment,
            executionType: executionType,
            trackingMode: .repsWeight,
            isBodyweight: entry.map { isBodyweightSource(for: $0, exercise: exercise) } ?? false,
            context: context
        )
        let best = SetLogQueries.lastBestSet(exercise: exercise, equipment: equipment, executionType: executionType, scopesByExecutionType: splits, excluding: session, context: context)
        let weightOptions = (equipment ?? exercise.weightedEquipment)?.sortedWeightCombos.map(\.value) ?? []
        return (
            reps: record?.reps ?? best?.reps ?? entry?.startingReps ?? 8,
            weight: record?.weight ?? best?.weight ?? entry?.startingWeight ?? weightOptions.first ?? 0
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
        let carry = carryoverValues(for: entry, exercise: exercise, key: key)
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
        // The rung actually being performed, which the progression menu may have changed
        // since this entry started. Everything below reads this, never `entry.exercise`.
        let performed = resolvedExercise(for: entry)
        // Resolved the same way the steppers display it, so logging a set the user
        // never touched saves exactly the value they were shown.
        let values = values ?? performed.map { draftValues(entry: entry, exercise: $0, key: key) }
        let reps = values?.reps ?? draftReps[key] ?? 8

        // The weight comes from whichever source this exercise is set to — typed number,
        // bodyweight zero, or the stepper's draft — so what's saved is what was shown.
        let resolved = performed.map { resolvedWeight(entry: entry, exercise: $0, key: key) }
        let weight = resolved?.weight ?? values?.weight ?? draftWeight[key] ?? 0
        let isBodyweight = resolved?.isBodyweight ?? values?.isBodyweight ?? false

        let log = SetLog(
            session: session,
            repSectionExercise: entry,
            exercise: performed,
            exerciseNameSnapshot: performed?.displayName,
            setIndex: key.index,
            reps: reps,
            weight: weight,
            weightUnit: performed.map { activeWeightUnit(for: entry, exercise: $0) } ?? AppSettings.weightUnit,
            isBodyweight: isBodyweight ? true : nil,
            side: key.side,
            repeatIndex: currentRepeat,
            // The equipment is always recorded now, typed weight or not — a record filed
            // under a null equipment is keyed apart from the real one.
            equipment: performed.flatMap { chosenEquipment(for: entry, exercise: $0) },
            isManualWeight: manualWeightFlag(
                weight: weight,
                options: performed.map { activeWeightOptions(for: entry, exercise: $0) } ?? []
            ),
            // Stamped whether or not this exercise splits records: the flag can be turned
            // on later, and history that never recorded the type could never be split.
            executionType: performed.flatMap { chosenExecutionType(for: entry, exercise: $0) }
        )
        context.insert(log)
        session.markDirty()
        try? context.save()

        recordIfBest(
            entry: entry,
            trackingMode: .repsWeight,
            reps: reps,
            weight: weight,
            holdSeconds: nil,
            isBodyweight: isBodyweight,
        )
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
            guard let exercise = resolvedExercise(for: entry) else { return nil }
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

        // A hold can be loaded (a weighted plank, a weighted dead hang), so the load is
        // resolved and stored exactly as it is for a reps/weight set. `reps` stays the
        // `0` sentinel — `holdSeconds` is what makes this a hold — but weight,
        // equipment and the bodyweight flag are all real values now rather than being
        // dropped while a derived `weightUnit` was stored anyway.
        let performed = resolvedExercise(for: entry)
        let resolved = performed.map { resolvedWeight(entry: entry, exercise: $0, key: key) }
        let weight = resolved?.weight ?? 0
        let isBodyweight = resolved?.isBodyweight ?? false

        let log = SetLog(
            session: session,
            repSectionExercise: entry,
            exercise: performed,
            exerciseNameSnapshot: performed?.displayName,
            setIndex: key.index,
            reps: 0,
            weight: weight,
            weightUnit: performed.map { activeWeightUnit(for: entry, exercise: $0) } ?? AppSettings.weightUnit,
            holdSeconds: holdSeconds,
            isBodyweight: isBodyweight ? true : nil,
            side: key.side,
            repeatIndex: currentRepeat,
            // The equipment is always recorded now, typed weight or not — a record filed
            // under a null equipment is keyed apart from the real one.
            equipment: performed.flatMap { chosenEquipment(for: entry, exercise: $0) },
            isManualWeight: manualWeightFlag(
                weight: weight,
                options: performed.map { activeWeightOptions(for: entry, exercise: $0) } ?? []
            ),
            // Stamped whether or not this exercise splits records: the flag can be turned
            // on later, and history that never recorded the type could never be split.
            executionType: performed.flatMap { chosenExecutionType(for: entry, exercise: $0) }
        )
        context.insert(log)
        session.markDirty()
        try? context.save()

        recordIfBest(
            entry: entry,
            trackingMode: .maxHoldTime,
            reps: nil,
            weight: weight,
            holdSeconds: holdSeconds,
            isBodyweight: isBodyweight,
        )
    }

    /// Promotes a just-logged result to the personal record when it beats the standing
    /// one, filing the old value into history. Silent by design — a record is worth
    /// seeing afterwards, not worth interrupting a set for.
    ///
    /// A typed weight counts like any other: it now carries the equipment it was
    /// performed on, so its record files under that equipment rather than under a null
    /// one the Records screen would key separately.
    private func recordIfBest(
        entry: RepSectionExercise,
        trackingMode: RepExerciseTrackingMode,
        reps: Int?,
        weight: Double?,
        holdSeconds: Int?,
        isBodyweight: Bool
    ) {
        guard let exercise = resolvedExercise(for: entry) else { return }
        // Before the `beats` guard below, which returns early on a set that didn't break
        // any record — reaching a harder rung at all is the achievement here, whatever
        // the numbers were.
        raiseReachedLevel(performing: exercise)
        let equipment = isBodyweight ? nil : chosenEquipment(for: entry, exercise: exercise)
        let executionType = recordExecutionType(for: entry, exercise: exercise)
        let existing = PersonalRecordQueries.current(
            for: exercise,
            equipment: equipment,
            executionType: executionType,
            trackingMode: trackingMode,
            isBodyweight: isBodyweight,
            context: context
        )

        guard PersonalRecordQueries.beats(
            record: existing,
            trackingMode: trackingMode,
            reps: reps,
            weight: weight,
            holdSeconds: holdSeconds,
            isBodyweight: isBodyweight
        ) else { return }

        PersonalRecordQueries.setRecord(
            for: exercise,
            equipment: equipment,
            executionType: executionType,
            existing: existing,
            trackingMode: trackingMode,
            reps: reps,
            weight: weight,
            holdSeconds: holdSeconds,
            isBodyweight: isBodyweight,
            weightUnit: activeWeightUnit(for: entry, exercise: exercise),
            context: context
        )
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
