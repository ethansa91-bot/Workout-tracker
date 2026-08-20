import SwiftUI
import SwiftData

/// Shown right after a session finishes: the result is saved locally, and syncs to the
/// user's other devices via CloudKit automatically in the background.
struct SessionSummaryView: View {
    let session: WorkoutSession
    let workout: Workout
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var noteTexts: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Workout Complete!")
                        .font(.appSerif(.title))
                    Text(workout.name)
                        .font(.headline)
                        .foregroundStyle(Color.appInkMuted)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 0) {
                            LabeledContent("Duration", value: durationString)
                                .padding(12)
                            Divider()
                            LabeledContent("Sets logged", value: "\(loggedSetCount)")
                                .padding(12)
                        }
                        .cardStyle(cornerRadius: 14)

                        if !distinctExercises.isEmpty {
                            notesCard
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 12) {
                    Button {
                        saveNotesAndFinish()
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationBarBackButtonHidden(true)
            .onAppear(perform: primeNoteTexts)
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notes").font(.headline)
            ForEach(distinctExercises, id: \.id) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                    TextField("Add a note…", text: noteBinding(for: exercise), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle(cornerRadius: 14)
    }

    /// Every exercise involved in this session, de-duplicated and in first-seen order —
    /// the set of exercises the notes card offers a note field for. Rep and time
    /// sections are read from their logs; EMOM/AMRAP sections log nothing at all (no
    /// `SetLog`/`StepLog` rows are ever created for them), so their exercises are read
    /// directly from the workout's sections instead — the only place notes are ever
    /// offered for those two section types, since their in-session runners don't show
    /// the note control.
    private var distinctExercises: [Exercise] {
        var seen = Set<UUID>()
        var result: [Exercise] = []
        let loggedExercises = session.setLogs.compactMap(\.exercise) + session.stepLogs.compactMap { $0.timeSectionStep?.exercise }
        let quickExercises = (session.workout?.sections ?? [])
            .filter { $0.sectionType == .emom || $0.sectionType == .amrap }
            .flatMap { $0.sortedQuickExercises.compactMap(\.exercise) }
        for exercise in loggedExercises + quickExercises where seen.insert(exercise.id).inserted {
            result.append(exercise)
        }
        return result
    }

    private func noteBinding(for exercise: Exercise) -> Binding<String> {
        Binding(
            get: { noteTexts[exercise.id] ?? "" },
            set: { noteTexts[exercise.id] = $0 }
        )
    }

    private func primeNoteTexts() {
        for note in session.exerciseNotes {
            if let exerciseID = note.exercise?.id {
                noteTexts[exerciseID] = note.text
            }
        }
    }

    private var loggedSetCount: Int {
        session.setLogs.filter { !$0.isCancelled }.count
    }

    private var durationString: String {
        let total = Int(session.elapsedSeconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func saveNotesAndFinish() {
        for exercise in distinctExercises {
            guard let text = noteTexts[exercise.id], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let note = ExerciseSessionNote.findOrCreate(session: session, exercise: exercise, context: context)
            note.text = text
            note.updatedAt = .now
        }
        try? context.save()
        onDone()
    }
}
