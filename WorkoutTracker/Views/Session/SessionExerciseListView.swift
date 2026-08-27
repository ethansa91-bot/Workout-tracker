import SwiftUI
import SwiftData

/// The whole workout, laid out section by section, shown over a running session so you
/// can see what's behind and ahead of you without leaving the exercise you're on.
///
/// Read-only on purpose: tapping a row does nothing. Jumping between arbitrary sections
/// would need session state rewound or fast-forwarded (see `TimeSessionRunnerView`'s
/// confirm-then-jump flow, which only moves within one section), and that isn't what
/// this panel is for.
struct SessionExerciseListView: View {
    let session: WorkoutSession
    let sections: [WorkoutSection]
    let onClose: () -> Void

    /// One row: an exercise, a rest, or a round, already resolved to a display string.
    private struct Row: Identifiable {
        let id: UUID
        let position: Int
        let title: String
        let detail: String?
        /// The follow-along step's own color, so a colored step keeps its identity here.
        var tint: Color?
        /// True for the single row the session is on right now.
        let isCurrent: Bool
    }

    private struct SectionGroup: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let rows: [Row]
        /// The whole section is the current one — used to mark an AMRAP section, which
        /// has no per-row position of its own.
        let isCurrent: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Nothing is drawn over the running workout — no dimming, no blur — so
                // the left of the screen looks exactly as it does with the panel closed.
                // It does take touches while the panel is open, though: a tap out here
                // closes the panel and stops there rather than also reaching the control
                // underneath, so dismissing can't skip an exercise on the way out.
                //
                // `contentShape` is what makes a clear layer hit-testable at all —
                // without it the tap falls straight through and nothing closes.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                panel
                    .frame(width: geometry.size.width * 0.5)
            }
        }
    }

    private var panel: some View {
        // No header: the ☰ button toggles this panel and a tap outside closes it, so a
        // title bar and an ✕ would only cost rows their vertical space.
        list
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.rows) { row in
                                rowView(row)
                                    .id(row.id)
                            }
                        } header: {
                            sectionHeader(group)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .onAppear {
                // Opens on whatever you're doing now rather than at the top of a long
                // workout.
                if let id = currentRowID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ group: SectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(group.isCurrent ? Color.appAccent : Color.appInk)
            Text(group.subtitle)
                .font(.caption2)
                .foregroundStyle(Color.appInkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NumberBadge(
                number: row.position,
                tint: row.isCurrent ? .white : (row.tint ?? Color.appInkMuted),
                size: 22
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.subheadline)
                    .foregroundStyle(row.isCurrent ? .white : Color.appInk)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(row.isCurrent ? .white.opacity(0.85) : Color.appRust)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(row.isCurrent ? Color.appAccent : Color.clear)
    }

    // MARK: - Data

    private var currentRowID: UUID? {
        groups.flatMap(\.rows).first(where: \.isCurrent)?.id
    }

    /// Which index means "where you are" depends on the section type — the same mapping
    /// the bottom progress bar uses, so the highlight and "Exercise X of Y" can't
    /// disagree.
    private func currentRowIndex(in section: WorkoutSection) -> Int? {
        switch section.sectionType {
        case .time, .emom: return session.currentStepIndex
        case .rep: return session.currentExerciseIndex
        // One countdown with every exercise live at once — no single row is current.
        case .amrap: return nil
        }
    }

    private var groups: [SectionGroup] {
        sections.enumerated().map { sectionIndex, section in
            let isCurrentSection = sectionIndex == session.currentSectionIndex
            let activeIndex = isCurrentSection ? currentRowIndex(in: section) : nil

            return SectionGroup(
                id: section.id,
                title: section.displayName,
                subtitle: subtitle(for: section),
                rows: rows(for: section, activeIndex: activeIndex),
                isCurrent: isCurrentSection
            )
        }
    }

    private func subtitle(for section: WorkoutSection) -> String {
        var parts = [section.sectionType.pillLabel]
        if section.effectiveRepeatCount > 1 {
            parts.append("×\(section.effectiveRepeatCount)")
        }
        parts.append(formattedEstimate(estimatedSectionSeconds(section)))
        return parts.joined(separator: " · ")
    }

    /// Get Ready and Rest steps are included, unlike the editing list: the runner plays
    /// them, so leaving them out would make the list disagree with what actually happens.
    private func rows(for section: WorkoutSection, activeIndex: Int?) -> [Row] {
        switch section.sectionType {
        case .time:
            return section.sortedTimeSteps.enumerated().map { index, step in
                Row(
                    id: step.id,
                    position: index + 1,
                    title: stepTitle(step),
                    detail: "\(step.durationSeconds)s",
                    tint: step.resolvedColor.color,
                    isCurrent: index == activeIndex
                )
            }
        case .rep:
            return section.sortedRepExercises.enumerated().map { index, entry in
                Row(
                    id: entry.id,
                    position: index + 1,
                    title: entry.exercise?.displayName ?? "Exercise",
                    detail: repDetail(entry),
                    isCurrent: index == activeIndex
                )
            }
        case .emom, .amrap:
            // Every exercise runs against the section's one timer, so these are listed
            // for reference and none of them is individually "current".
            return section.sortedQuickExercises.enumerated().map { index, entry in
                Row(
                    id: entry.id,
                    position: index + 1,
                    title: entry.exercise?.displayName ?? "Exercise",
                    detail: nil,
                    isCurrent: false
                )
            }
        }
    }

    private func stepTitle(_ step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    private func repDetail(_ entry: RepSectionExercise) -> String {
        var parts = ["\(entry.targetSets) set\(entry.targetSets == 1 ? "" : "s")"]
        if entry.trackingMode == .maxHoldTime {
            parts.append("max time")
        }
        if entry.isTrackingSides {
            parts.append("L/R")
        }
        return parts.joined(separator: " · ")
    }
}
