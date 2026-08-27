import SwiftUI
import SwiftData

/// The load a rep entry defaults to: one of the exercise's weighted equipment, or
/// bodyweight. Two settings back it — `preferredEquipment` and `prefersBodyweight` —
/// but they're one choice to the user, so they're picked as one here rather than as a
/// menu plus a separate toggle.
///
/// Shared by the gear popover (`ExerciseSettingsPopover`) and the inline section editor
/// (`SectionCardView`'s per-exercise gear), which carried byte-identical copies of
/// this before.
struct EquipmentSourcePicker: View {
    @Bindable var entry: RepSectionExercise
    let context: ModelContext
    /// The popover styles its own rows; the section editor uses a plain labeled picker.
    var showsInlineLabel: Bool = true

    /// Distinguishes "bodyweight" from any equipment id without a second binding.
    private static let bodyweightTag = UUID()

    private var options: [Equipment] { entry.exercise?.weightedEquipmentOptions ?? [] }
    private var allowsBodyweight: Bool { entry.exercise?.allowsBodyweightSource ?? false }

    /// Nothing to ask when there's only one possible answer. Bodyweight counts as a
    /// real alternative, so a single weighted item plus bodyweight is still a choice.
    var hasChoice: Bool {
        options.count > 1 || (allowsBodyweight && !options.isEmpty)
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: {
                if entry.prefersBodyweight { return Self.bodyweightTag }
                // Falls back to the catalog's own resolution rather than the
                // alphabetically first item, so the builder shows the same default the
                // runner will actually use.
                return entry.preferredEquipment?.id ?? entry.exercise?.weightedEquipment?.id
            },
            set: { newID in
                if newID == Self.bodyweightTag {
                    entry.prefersBodyweight = true
                    entry.preferredEquipment = nil
                } else {
                    entry.prefersBodyweight = false
                    entry.preferredEquipment = options.first { $0.id == newID }
                }
                entry.markDirty()
                try? context.save()
            }
        )
    }

    var body: some View {
        if hasChoice {
            if showsInlineLabel {
                HStack {
                    Text("Equipment:")
                        .font(.subheadline)
                    Spacer()
                    picker
                        .labelsHidden()
                        .tint(Color.appRust)
                }
            } else {
                picker
            }
        }
    }

    private var picker: some View {
        Picker("Equipment", selection: selection) {
            ForEach(options) { item in
                Text(item.name).tag(Optional(item.id))
            }
            if allowsBodyweight {
                Text("Bodyweight").tag(Optional(Self.bodyweightTag))
            }
        }
    }
}
