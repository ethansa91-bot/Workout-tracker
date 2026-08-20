import SwiftUI

/// The catalog's persistent description for an exercise (`Exercise.notes`), shown under
/// the media box during a session — form cues that are worth reading whether or not the
/// exercise happens to have a photo or video.
///
/// Distinct from `SessionNoteRow`, which edits the user's own per-session note.
/// This one is read-only reference text that travels with the exercise.
struct ExerciseDescriptionView: View {
    enum Style {
        /// Follow Along and Reps show one exercise at a time, with room to read — the
        /// text sits under the media and renders nothing when there are no notes.
        case alwaysVisible
        /// The EMOM/AMRAP grids show many small cells at once. Here the text lives
        /// behind a button that opens a sheet, and the button's slot is reserved even
        /// when an exercise has no notes: cells in a `LazyVGrid` row are height-matched,
        /// so a cell that's shorter by one button throws the whole row's media out of
        /// alignment.
        case gridButton
        /// The Rep runner on iPhone, where vertical space is scarce: an inline
        /// disclosure that expands the text in place rather than opening a sheet.
        case collapsible
    }

    let exercise: Exercise
    var style: Style = .alwaysVisible

    @State private var showingSheet = false
    @State private var isExpanded = false

    /// Reserved height for the grid button, paid whether or not there's anything to
    /// show, so every cell in a row stays exactly the same height.
    private static let gridButtonHeight: CGFloat = 18

    /// Blank notes are treated as no notes — most catalog exercises have none, and an
    /// empty placeholder mid-workout is just noise.
    private var notes: String? {
        guard let trimmed = exercise.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var body: some View {
        switch style {
        case .alwaysVisible:
            if let notes {
                descriptionText(notes)
            }
        case .gridButton:
            gridButton
        case .collapsible:
            collapsible
        }
    }

    /// Accordion, not a sheet — the text is short enough to read in place, and a sheet
    /// for one paragraph mid-set is more disruptive than the reading is worth.
    @ViewBuilder
    private var collapsible: some View {
        if let notes {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("Description")
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    descriptionText(notes)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func descriptionText(_ notes: String) -> some View {
        Text(notes)
            .font(.footnote)
            .foregroundStyle(Color.appInkMuted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opens in a sheet rather than expanding in place — an inline accordion inside a
    /// grid cell pushes every row below it down the moment it opens.
    @ViewBuilder
    private var gridButton: some View {
        if let notes {
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Description")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(Color.appAccent)
                .frame(height: Self.gridButtonHeight)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSheet) {
                descriptionSheet(notes)
            }
        } else {
            // Same height as the button above — keeps every cell in the row aligned.
            Color.clear
                .frame(height: Self.gridButtonHeight)
        }
    }

    private func descriptionSheet(_ notes: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(Color.appInk)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.appBackground)
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
