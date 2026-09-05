import SwiftUI

/// Which side a Follow Along step or an EMOM/AMRAP entry works — the side counterpart to
/// `ExecutionTypePicker`, and deliberately the same shape so the two read as one pair of
/// settings rather than two conventions.
///
/// Only offered for an exercise the catalog marks `isOneSided`: naming a side on a
/// two-handed movement would be a claim the rest of the app can't honour.
///
/// Not the same question as a rep entry's "Track L/R", which means *log each set twice,
/// once per side*. Here the step **is** one side, and the other side is a separate step —
/// which is why rep entries don't get this picker and these three types don't get that
/// toggle.
struct SidePicker: View {
    let exercise: Exercise?
    @Binding var selection: SetSide?

    /// "Both" rather than "None": a step with no side isn't missing an answer, it works
    /// both sides — and that's what the name reads as when nothing is appended.
    private static let bothLabel = "Both"

    var hasChoice: Bool { exercise?.isOneSided == true }

    var body: some View {
        if hasChoice {
            // The long form, matching the name this choice ends up qualifying: the row
            // reads "Side: Left side" the way the step will read "Split Squat, Left side".
            SettingMenu(title: "Side", value: selection?.longLabel ?? Self.bothLabel) {
                Button(Self.bothLabel) { selection = nil }
                ForEach(SetSide.allCases, id: \.self) { side in
                    Button(side.longLabel) { selection = side }
                }
            }
        }
    }
}
