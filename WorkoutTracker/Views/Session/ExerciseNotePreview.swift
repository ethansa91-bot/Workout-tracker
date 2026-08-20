import SwiftUI
import SwiftData

/// Read-only view of what's been noted about an exercise: the previous session's note —
/// the one actually worth reading mid-set — plus this session's own note once it's been
/// written, in a lighter treatment underneath.
///
/// Read-only: the Follow Along runner shows this, since notes there are entered at the
/// end of the workout rather than mid-set. The Rep runner uses `SessionNoteRow`, which
/// both displays and edits.
struct ExerciseNotePreview: View {
    @Bindable var session: WorkoutSession
    let exercise: Exercise

    @Environment(\.modelContext) private var context

    /// From the observed relationship rather than a fetch — `pastNotes` deliberately
    /// excludes the current session, so a note just written can only be seen this way
    /// (and, being observed, it appears the moment it's saved).
    private var currentNoteText: String? {
        let text = session.exerciseNotes
            .first { $0.exercise?.id == exercise.id }?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    private var lastNoteText: String? {
        ExerciseSessionNoteQueries.pastNotes(for: exercise, excluding: session, context: context)
            .last?
            .text
    }

    var body: some View {
        if lastNoteText != nil || currentNoteText != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let lastNoteText {
                    labelled("Last note", lastNoteText, isPrimary: true)
                }
                if let currentNoteText {
                    labelled("This session", currentNoteText, isPrimary: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The previous note carries the weight here; this session's own note is
    /// supplementary — it's what you just wrote, so it needs confirming, not reading.
    private func labelled(_ title: String, _ text: String, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(isPrimary ? .footnote : .caption)
                .foregroundStyle(isPrimary ? Color.appInkMuted : .secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
