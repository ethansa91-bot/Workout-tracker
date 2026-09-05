import SwiftUI
import SwiftData

/// How a workout performs one exercise — the execution-type counterpart to
/// `EquipmentSourcePicker`, and deliberately the same shape so the two read as one pair of
/// settings rather than two conventions.
///
/// Takes a plain `Binding` and an option list rather than an entry, because both a rep
/// entry and a Follow Along step need this and they share no protocol. Persistence belongs
/// to the binding's setter for the same reason — each caller already knows how to save.
///
/// "None" is a first-class option, not an empty state: an exercise can carry three types
/// and a workout can still legitimately not name one, and nil is what every record made
/// before execution types existed is filed under.
struct ExecutionTypePicker: View {
    let options: [ExecutionType]
    @Binding var selection: ExecutionType?

    /// Distinguishes "no type" from any type id without a second binding — the same trick
    /// `EquipmentSourcePicker` uses for bodyweight.
    private static let noneTag = UUID()

    /// Nothing to ask when the exercise carries no types at all. One type is still a
    /// choice, unlike equipment, because "none" is a meaningful alternative to it.
    var hasChoice: Bool { !options.isEmpty }

    var body: some View {
        if hasChoice {
            SettingMenu(title: "Execution", value: selection?.name ?? "None") {
                Button("None") { selection = nil }
                ForEach(options) { type in
                    Button(type.name) { selection = type }
                }
            }
        }
    }
}
