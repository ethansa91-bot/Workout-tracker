import SwiftUI

/// Shared phrasing for the section editors' repeat stepper, so all three read the same.
func repeatLabel(_ count: Int) -> String {
    count <= 1 ? "Repeat: none" : "Repeat: \(count)×"
}

/// "Abs · Round 2 of 3" — a section's name with the pass number, or just the name when
/// it runs once. Shared so the runner header and the History detail can't drift on how
/// a round is worded.
func sectionRoundTitle(_ section: WorkoutSection, repeatIndex: Int, name: String? = nil) -> String {
    let base = name ?? section.displayName
    let total = section.effectiveRepeatCount
    guard total > 1 else { return base }
    return "\(base) · Round \(min(repeatIndex + 1, total)) of \(total)"
}

/// The section you're in, shown at the top of a runner's exercise area — with the pass
/// number when the section repeats ("Abs · Round 2 of 3").
///
/// The section name isn't shown anywhere else during a workout, so this is the only
/// place a mixed workout tells you which part you're on.
struct SectionHeaderLabel: View {
    let section: WorkoutSection
    let repeatIndex: Int
    /// Follow Along tints this with the current step's color so the title reads as part
    /// of that step. `nil` keeps the muted gray the other runners use.
    var tint: Color?

    private var text: String {
        // The "Section:" prefix belongs to the Follow Along header, where the row is
        // pinned and needs to say what it is. The other runners keep the bare caption.
        let name = tint == nil ? section.displayName : "Section: \(section.displayName)"
        return sectionRoundTitle(section, repeatIndex: repeatIndex, name: name)
    }

    var body: some View {
        Text(text)
            .font(tint == nil ? .caption.weight(.semibold) : .headline)
            .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint!))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
