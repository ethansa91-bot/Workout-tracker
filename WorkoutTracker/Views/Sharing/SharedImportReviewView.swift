import SwiftUI
import SwiftData

/// One local row an incoming item can be pointed at.
struct CatalogCandidate: Identifiable, Hashable {
    let id: UUID
    let name: String
}

/// What a download will do to the library, before it does it.
///
/// This screen exists because the alternative — silently reusing whatever local row
/// happens to share a name — makes a decision on the user's behalf they may well
/// disagree with. Everything it offers is non-destructive: the default for a conflict is
/// Merge, and no choice here ever deletes a local row or splits one in two.
struct SharedImportReviewView: View {
    @State var plan: SharedWorkoutPlan
    let onImport: (SharedWorkoutPlan) -> Void

    @Environment(\.dismiss) private var dismiss

    @Query private var allExercises: [Exercise]
    @Query private var allEquipment: [Equipment]
    @Query private var allMuscles: [Muscle]
    @Query private var allExerciseCategories: [ExerciseCategory]
    @Query private var allMuscleCategories: [MuscleCategory]

    /// Presented sheets. Hoisted out of the rows so the generic decision row doesn't have
    /// to own presentation state of its own.
    @State private var comparison: Comparison?
    @State private var linking: Linking?

    var body: some View {
        NavigationStack { reviewList }
    }

    private var reviewList: some View {
        List {
            summarySection

            decisionSection(
                title: "Exercises",
                decisions: $plan.catalog.exercises,
                icon: "figure.strengthtraining.traditional",
                candidates: candidates(allExercises, name: \.name)
            )
            decisionSection(
                title: "Equipment",
                decisions: $plan.catalog.equipment,
                icon: "dumbbell",
                candidates: candidates(allEquipment, name: \.name)
            )
            decisionSection(
                title: "Muscles",
                decisions: $plan.catalog.muscles,
                icon: "figure.arms.open",
                candidates: candidates(allMuscles, name: \.name)
            )
            decisionSection(
                title: "Exercise Categories",
                decisions: $plan.catalog.exerciseCategories,
                icon: "tag",
                candidates: candidates(allExerciseCategories, name: \.name)
            )
            decisionSection(
                title: "Muscle Categories",
                decisions: $plan.catalog.muscleCategories,
                icon: "tag",
                candidates: candidates(allMuscleCategories, name: \.name)
            )

            automaticMatchSection
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(
                title: plan.displayTitle,
                subtitle: "\(plan.sectionCount) section\(plan.sectionCount == 1 ? "" : "s") · review what gets added to your library"
            )
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onImport(plan)
                dismiss()
            } label: {
                Text(plan.workoutCount == 1 ? "Save Workout" : "Save \(plan.workoutCount) Workouts")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.appAccent.opacity(0.25))
            .foregroundStyle(Color.appAccent)
            .padding()
            .background(.thickMaterial)
        }
        .sheet(item: $comparison) { subject in
            CatalogConflictDetailView(subject: subject)
        }
        .sheet(item: $linking) { subject in
            CatalogLinkPickerView(subject: subject)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                summaryRow(plan.catalog.willAddCount, "will be added to your library", Color.appAccent)
                summaryRow(plan.catalog.conflictCount, "already exist and differ", Color.appRust)
                summaryRow(plan.catalog.linkedCount, "linked to something you already have", Color.appAccent)
                summaryRow(plan.catalog.unchangedCount, "already match — nothing to do", Color.appInkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .fullBleedRow(isLast: true)
        } header: {
            ListBandHeader(
                title: "Summary",
                subtitle: "Nothing already in your library is deleted or duplicated, whatever you choose."
            )
        }
    }

    @ViewBuilder
    private func summaryRow(_ count: Int, _ label: String, _ tint: Color) -> some View {
        if count > 0 {
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(.appSerif(.subheadline, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }

    /// Everything resolved without asking, listed last — after every section that needs
    /// a decision, so it never comes between the user and the choices they have to make.
    ///
    /// Listed rather than merely counted: "14 already match" doesn't let you check the
    /// importer matched the right 14, and a wrong match here silently points the workout
    /// at the wrong exercise.
    @ViewBuilder
    private var automaticMatchSection: some View {
        let matches = plan.catalog.automaticMatches
        if !matches.isEmpty {
            Section {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.incomingName)
                            .foregroundStyle(Color.appInk)
                        Text(matchDetail(match))
                            .font(.caption)
                            .foregroundStyle(Color.appInkMuted)
                    }
                    .padding(.vertical, 2)
                    .fullBleedRow(isLast: index == matches.count - 1)
                }
            } header: {
                ListBandHeader(
                    title: "Already in Your Library",
                    subtitle: "Matched exactly — used as-is, nothing added or changed."
                )
            }
        }
    }

    private func matchDetail(_ match: CatalogImportPlan.Match) -> String {
        guard let localName = match.localName, localName != match.incomingName else {
            return match.type
        }
        // Worth spelling out when the names differ: an id match across two catalogs can
        // pair rows one side has renamed, and that's exactly the case to eyeball.
        return "\(match.type) · matched your “\(localName)”"
    }

    /// One type's decisions. Rows that matched something identical are omitted here and
    /// listed in `automaticMatchSection` instead.
    @ViewBuilder
    private func decisionSection<DTO>(
        title: String,
        decisions: Binding<[CatalogDecision<DTO>]>,
        icon: String,
        candidates: [CatalogCandidate]
    ) -> some View {
        let indices = decisions.wrappedValue.indices.filter {
            decisions.wrappedValue[$0].isConflict || decisions.wrappedValue[$0].isNew
        }

        if !indices.isEmpty {
            Section {
                ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                    CatalogDecisionRow(
                        decision: decisions[index],
                        icon: icon,
                        candidates: candidates,
                        onCompare: { comparison = $0 },
                        onLink: { linking = $0 }
                    )
                    .fullBleedRow(isLast: position == indices.count - 1)
                }
            } header: {
                ListBandHeader(title: title)
            }
        }
    }

    private func candidates<T: SyncableModel>(
        _ rows: [T],
        name: KeyPath<T, String>
    ) -> [CatalogCandidate] {
        rows.filter { $0.deletedAt == nil }
            .map { CatalogCandidate(id: $0.id, name: $0[keyPath: name]) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Sheet subjects

    /// Side-by-side comparison for one conflicting item. Carries plain values plus a
    /// setter, so it never has to be generic over the DTO.
    struct Comparison: Identifiable {
        let id: UUID
        let title: String
        let localName: String?
        let differences: [CatalogDifference]
        let current: CatalogResolution
        let apply: (CatalogResolution) -> Void
    }

    /// Picking an existing local row for an unmatched item.
    struct Linking: Identifiable {
        let id: UUID
        let title: String
        let candidates: [CatalogCandidate]
        let current: CatalogResolution
        let apply: (CatalogResolution) -> Void
    }
}

// MARK: - Row

/// One incoming catalog row and its resolution control.
private struct CatalogDecisionRow<DTO>: View {
    @Binding var decision: CatalogDecision<DTO>
    let icon: String
    let candidates: [CatalogCandidate]
    let onCompare: (SharedImportReviewView.Comparison) -> Void
    let onLink: (SharedImportReviewView.Linking) -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, tint: tint, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(decision.incomingName)
                    .foregroundStyle(Color.appInk)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Menu {
                if decision.isConflict {
                    // Merge first: it's the default, and the only option that can't lose
                    // anything the user already had.
                    choice(.merge, "Merge both")
                    choice(.keepMine, "Keep mine")
                    choice(.useTheirs, "Use theirs")
                    Divider()
                    Button {
                        onCompare(.init(
                            id: decision.incomingID,
                            title: decision.incomingName,
                            localName: decision.localName,
                            differences: decision.differences,
                            current: decision.resolution,
                            apply: { decision.resolution = $0 }
                        ))
                    } label: {
                        Label("Compare…", systemImage: "arrow.left.arrow.right")
                    }
                } else {
                    choice(.createNew, "Add new")
                    Divider()
                    Button {
                        onLink(.init(
                            id: decision.incomingID,
                            title: decision.incomingName,
                            candidates: candidates,
                            current: decision.resolution,
                            apply: { decision.resolution = $0 }
                        ))
                    } label: {
                        Label("Link to existing…", systemImage: "link")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(resolutionLabel).font(.subheadline)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(Color.appAccent)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func choice(_ resolution: CatalogResolution, _ label: String) -> some View {
        Button {
            decision.resolution = resolution
        } label: {
            if decision.resolution == resolution {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private var tint: Color {
        if case .link = decision.resolution { return Color.appAccent }
        return decision.isConflict ? Color.appRust : Color.appAccent
    }

    private var subtitle: String {
        if case .link(let localID) = decision.resolution {
            let name = candidates.first { $0.id == localID }?.name ?? "an existing item"
            return "Will use your “\(name)” — nothing added"
        }
        if decision.isConflict {
            let fields = decision.differences.prefix(3).map(\.field).joined(separator: ", ")
            let extra = decision.differences.count - min(3, decision.differences.count)
            return "Already in your library · differs in \(fields)" + (extra > 0 ? " +\(extra) more" : "")
        }
        return "Not in your library yet"
    }

    private var resolutionLabel: String {
        switch decision.resolution {
        case .merge: return "Merge"
        case .keepMine: return "Keep mine"
        case .useTheirs: return "Use theirs"
        case .createNew: return "Add new"
        case .link: return "Linked"
        case .identical: return "Unchanged"
        }
    }
}
