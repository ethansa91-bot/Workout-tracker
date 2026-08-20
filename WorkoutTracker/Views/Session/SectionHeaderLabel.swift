import SwiftUI

/// Shared phrasing for the section editors' repeat stepper, so all three read the same.
func repeatLabel(_ count: Int) -> String {
    count <= 1 ? "Repeat: none" : "Repeat: \(count)×"
}

/// The section you're in, shown at the top of a runner's exercise area — with the pass
/// number when the section repeats ("Abs · Round 2 of 3").
///
/// The section name isn't shown anywhere else during a workout, so this is the only
/// place a mixed workout tells you which part you're on.
struct SectionHeaderLabel: View {
    let section: WorkoutSection
    let repeatIndex: Int

    private var text: String {
        let total = section.effectiveRepeatCount
        guard total > 1 else { return section.displayName }
        return "\(section.displayName) · Round \(min(repeatIndex + 1, total)) of \(total)"
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
