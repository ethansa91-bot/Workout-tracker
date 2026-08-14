import SwiftUI
import SwiftData

private enum WorkoutsPane: String, CaseIterable, Identifiable {
    case workouts, templates, library

    var id: String { rawValue }

    var label: String {
        switch self {
        case .workouts: return "Workouts"
        case .templates: return "Templates"
        case .library: return "Library"
        }
    }
}

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.createdAt, order: .reverse) private var allWorkouts: [Workout]

    @State private var selectedPane: WorkoutsPane = .workouts
    @State private var showingNewWorkoutSheet = false
    @State private var showingNewTemplateSheet = false
    @State private var newWorkoutDestination: WorkoutEditDestination?
    @State private var newTemplateDestination: WorkoutSection?

    private var workouts: [Workout] {
        allWorkouts.filter { $0.deletedAt == nil && !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                paneSelector
                Group {
                    switch selectedPane {
                    case .workouts: workoutsContent
                    case .templates: SectionTemplatesView()
                    case .library: LibraryHomeView()
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle(navigationTitleText)
            .toolbar {
                if selectedPane == .workouts {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            ArchivedWorkoutsView()
                        } label: {
                            Label("Archives", systemImage: "archivebox")
                        }
                    }
                }
                if selectedPane != .library {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if selectedPane == .workouts {
                                showingNewWorkoutSheet = true
                            } else {
                                showingNewTemplateSheet = true
                            }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewWorkoutSheet) {
                NewWorkoutSheet(onCreate: createWorkout)
            }
            .sheet(isPresented: $showingNewTemplateSheet) {
                NewSectionTemplateSheet(onCreate: createTemplate)
            }
            .navigationDestination(item: $newWorkoutDestination) { destination in
                switch destination {
                case .workout(let workout):
                    SessionRecapView(workout: workout)
                case .section(let section):
                    SectionEditorView(section: section, onSaveNavigatesToRecap: true)
                }
            }
            .navigationDestination(item: $newTemplateDestination) { section in
                SectionEditorView(section: section)
            }
        }
    }

    private var navigationTitleText: String {
        switch selectedPane {
        case .workouts: return "My Workouts"
        case .templates: return "Section Templates"
        case .library: return "Library"
        }
    }

    private var paneSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkoutsPane.allCases) { pane in
                    paneChip(pane)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func paneChip(_ pane: WorkoutsPane) -> some View {
        let isSelected = selectedPane == pane
        return Button {
            selectedPane = pane
        } label: {
            Text(pane.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.appAccent)
                .background(isSelected ? Color.appAccent : Color.appAccent.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.appAccent.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var workoutsContent: some View {
        if workouts.isEmpty {
            ContentUnavailableView(
                "No Workouts Yet",
                systemImage: "list.bullet.rectangle",
                description: Text("Tap + to build a time, repetition, or mixed workout.")
            )
        } else {
            List {
                Section {
                    ForEach(workouts) { workout in
                        NavigationLink {
                            SessionRecapView(workout: workout)
                        } label: {
                            workoutRow(workout)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                cloneWorkout(workout)
                            } label: {
                                Label("Clone", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                archiveWorkout(workout)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                cloneWorkout(workout)
                            } label: {
                                Label("Clone", systemImage: "doc.on.doc")
                            }
                            Button {
                                archiveWorkout(workout)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                } footer: {
                    Text("A lock means that workout has already been used and can't be edited or deleted. Swipe right on a workout to clone it, or left to archive it.")
                }
            }
            .themedListBackground()
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workoutTypeIcon(workout))
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name)
                StatusPill(text: workout.listTypeLabel, tint: .accentColor)
                if let notes = workout.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if workout.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func workoutTypeIcon(_ workout: Workout) -> String {
        workout.displayType.iconSymbolName
    }

    private func cloneWorkout(_ workout: Workout) {
        _ = WorkoutCloningService.clone(workout, context: context)
    }

    private func archiveWorkout(_ workout: Workout) {
        workout.isArchived = true
        workout.markDirty()
        try? context.save()
    }

    private func createWorkout(name: String, kind: WorkoutKind) {
        let workout = WorkoutEditingService.createWorkout(name: name, kind: kind, context: context)
        guard kind != .personalized else {
            newWorkoutDestination = .workout(workout)
            return
        }
        do {
            let section = try WorkoutEditingService.addSection(to: workout, type: kind == .byTime ? .time : .rep, context: context)
            newWorkoutDestination = .section(section)
        } catch {
            newWorkoutDestination = .workout(workout)
        }
    }

    private func createTemplate(name: String, type: WorkoutSectionType) {
        let section = WorkoutEditingService.createTemplate(name: name, type: type, context: context)
        newTemplateDestination = section
    }
}
