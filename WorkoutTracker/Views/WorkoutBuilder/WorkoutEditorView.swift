import SwiftUI
import SwiftData

private struct OverviewItem: Identifiable {
    let id: UUID
    let iconName: String
    let title: String
    let detail: String
    /// A follow-along exercise step's assigned color (`TimeSectionStep.color`), if any
    /// — `nil` for rest/get-ready steps and for rep-section exercises, which don't
    /// have per-exercise colors.
    var color: Color?
}

struct WorkoutEditorView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context

    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    private var isLocked: Bool { workout.isLocked }

    var body: some View {
        listContent
            .environment(\.editMode, $editMode)
            .themedListBackground()
            .navigationTitle(workout.name.isEmpty ? "Workout" : workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { mainToolbar }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            nameSection
            sectionsSection
        }
    }

    @ViewBuilder
    private var nameSection: some View {
        Section {
            TextField("Name", text: Binding(
                get: { workout.name },
                set: { newValue in
                    do { try WorkoutEditingService.rename(workout, to: newValue, context: context) }
                    catch { errorMessage = error.localizedDescription }
                }
            ))
            .disabled(isLocked)
            LabeledContent("Type", value: workout.displayType.label)
        }
    }

    @ViewBuilder
    private var sectionsSection: some View {
        Section("Sections") {
            if workout.sortedSections.isEmpty {
                Text("No sections yet").foregroundStyle(.secondary)
            }
            sectionRows
            addSectionMenu
        }
    }

    private var sectionRows: some View {
        ForEach(workout.sortedSections) { section in
            NavigationLink {
                SectionEditorView(section: section)
            } label: {
                sectionRow(section)
            }
            .swipeActions(edge: .leading) {
                cloneSectionButton(section)
            }
        }
        .onDelete(perform: deleteSectionsAction)
        .onMove(perform: moveSectionsAction)
    }

    @ViewBuilder
    private func cloneSectionButton(_ section: WorkoutSection) -> some View {
        if !isLocked {
            Button {
                cloneSection(section)
            } label: {
                Label("Clone Section", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }

    // Explicit optional-closure types here sidestep a real Swift inference limitation:
    // `isLocked ? nil : someFunctionReference` inline in a modifier argument position
    // fails to type-check ("ambiguous"/"failed to produce diagnostic") without one.
    private var deleteSectionsAction: ((IndexSet) -> Void)? {
        if isLocked { return nil }
        return deleteSections
    }

    private var moveSectionsAction: ((IndexSet, Int) -> Void)? {
        if isLocked { return nil }
        return moveSections
    }

    @ViewBuilder
    private var addSectionMenu: some View {
        if !isLocked {
            if workout.kind == .personalized {
                Menu {
                    Button("Follow Along Section") { addSection(.time) }
                    Button("Repetition Section") { addSection(.rep) }
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
            } else if workout.sortedSections.isEmpty {
                Button {
                    addSection(workout.kind == .byTime ? .time : .rep)
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                editMode = editMode.isEditing ? .inactive : .active
            } label: {
                Image(systemName: editMode.isEditing ? "checkmark" : "pencil")
            }
        }
    }

    private func sectionRow(_ section: WorkoutSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(systemName: section.sectionType == .time ? "timer" : "list.number")
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: section))
                    Text(section.sectionType == .time ? "\(section.sortedTimeSteps.count) steps" : "\(section.sortedRepExercises.count) exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(overviewItems(for: section)) { item in
                overviewItemRow(item)
            }
        }
        .padding(.vertical, 4)
    }

    /// One row per contained exercise/rest, shown directly under its section so the
    /// whole workout's contents are visible at a glance without navigating into each
    /// section.
    private func overviewItems(for section: WorkoutSection) -> [OverviewItem] {
        if section.sectionType == .time {
            return section.sortedTimeSteps.map { step in
                OverviewItem(
                    id: step.id,
                    iconName: overviewIcon(for: step),
                    title: overviewTitle(for: step),
                    detail: "\(step.durationSeconds)s",
                    color: step.effectiveColor?.color
                )
            }
        } else {
            return section.sortedRepExercises.map { entry in
                OverviewItem(
                    id: entry.id,
                    iconName: entry.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional",
                    title: entry.exercise?.name ?? "Exercise",
                    detail: repExerciseDetail(for: entry)
                )
            }
        }
    }

    private func repExerciseDetail(for entry: RepSectionExercise) -> String {
        switch entry.trackingMode {
        case .repsWeight:
            return "\(entry.targetSets) sets · rest \(entry.customRestSeconds.map { "\($0)s" } ?? "default")"
        case .maxHoldTime:
            return "\(entry.targetSets) sets · max hold · \(entry.headStartSeconds)s head start"
        }
    }

    private func overviewIcon(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional"
        case .rest: return "pause.circle"
        case .getReady: return "hourglass"
        }
    }

    private func overviewTitle(for step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.name ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    private func overviewItemRow(_ item: OverviewItem) -> some View {
        HStack {
            Image(systemName: item.iconName)
                .font(.caption)
                .foregroundStyle(item.color ?? .secondary)
                .frame(width: 20)
            Text(item.title)
                .font(.subheadline)
            Spacer()
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }

    private func displayName(for section: WorkoutSection) -> String {
        if let name = section.name, !name.isEmpty { return name }
        return section.sectionType == .time ? "Follow Along Section" : "Rep Section"
    }

    private func addSection(_ type: WorkoutSectionType) {
        do { _ = try WorkoutEditingService.addSection(to: workout, type: type, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteSections(at offsets: IndexSet) {
        let sections = workout.sortedSections
        for index in offsets {
            do { try WorkoutEditingService.deleteSection(sections[index], from: workout, context: context) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        do { try WorkoutEditingService.moveSections(in: workout, from: source, to: destination, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cloneSection(_ section: WorkoutSection) {
        do { _ = try WorkoutSectionCloningService.cloneSection(section, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
