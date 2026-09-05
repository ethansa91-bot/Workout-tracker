import SwiftUI
import SwiftData

/// The load an entry defaults to: one of the exercise's weighted equipment, or bodyweight.
/// Two settings back it — `preferredEquipment` and `prefersBodyweight` — but they're one
/// choice to the user, so they're picked as one here rather than as a menu plus a separate
/// toggle.
///
/// Takes bindings rather than a model, because a rep entry and a Follow Along step both
/// carry this pair and share no protocol — the same reason `ExecutionTypePicker` does.
/// The `RepSectionExercise` convenience init below keeps the original call shape.
struct EquipmentSourcePicker: View {
    let exercise: Exercise?
    @Binding var preferredEquipment: Equipment?
    @Binding var prefersBodyweight: Bool
    /// Persistence belongs to the caller: each one already knows what to mark dirty.
    var onChange: () -> Void

    /// Distinguishes "bodyweight" from any equipment id without a second binding.
    private static let bodyweightTag = UUID()

    private var options: [Equipment] { exercise?.weightedEquipmentOptions ?? [] }
    private var allowsBodyweight: Bool { exercise?.allowsBodyweightSource ?? false }

    /// Deferred to the catalog so the exercise page's "Default equipment" row and this
    /// picker are offered under exactly the same condition.
    var hasChoice: Bool {
        exercise?.hasEquipmentChoice ?? false
    }

    private var selectedName: String {
        Self.resolvedSourceName(
            exercise: exercise,
            preferredEquipment: preferredEquipment,
            prefersBodyweight: prefersBodyweight
        )
    }

    /// What this entry will actually be loaded with — the entry's own choice, else the
    /// catalog's resolution, else bodyweight.
    ///
    /// Static and shared with `exerciseSettingsSummary`, which names the same thing on the
    /// row outside this picker. The precedence mirrors `RepSessionRunnerView.weightSource`,
    /// which is the authority; a fourth copy of it would be a fourth chance for the
    /// builder to disagree with what the runner loads.
    static func resolvedSourceName(
        exercise: Exercise?,
        preferredEquipment: Equipment?,
        prefersBodyweight: Bool
    ) -> String {
        if prefersBodyweight { return "Bodyweight" }
        let options = exercise?.weightedEquipmentOptions ?? []
        let id = preferredEquipment?.id ?? exercise?.defaultWeightedEquipment?.id
        return options.first { $0.id == id }?.name ?? "Bodyweight"
    }

    var body: some View {
        if hasChoice {
            SettingMenu(title: "Equipment", value: selectedName) {
                ForEach(options) { item in
                    Button(item.name) { select(item.id) }
                }
                if allowsBodyweight {
                    Button("Bodyweight") { select(Self.bodyweightTag) }
                }
            }
        }
    }

    private func select(_ id: UUID) {
        if id == Self.bodyweightTag {
            prefersBodyweight = true
            preferredEquipment = nil
        } else {
            prefersBodyweight = false
            preferredEquipment = options.first { $0.id == id }
        }
        onChange()
    }
}

extension EquipmentSourcePicker {
    /// The original call shape, kept so the rep popover reads as it did.
    init(entry: RepSectionExercise, context: ModelContext) {
        self.init(
            exercise: entry.exercise,
            preferredEquipment: Binding(
                get: { entry.preferredEquipment },
                set: { entry.preferredEquipment = $0 }
            ),
            prefersBodyweight: Binding(
                get: { entry.prefersBodyweight },
                set: { entry.prefersBodyweight = $0 }
            ),
            onChange: {
                entry.markDirty()
                try? context.save()
            }
        )
    }

    /// A Follow Along step holds the same pair, for the same reason: a weighted plank is
    /// still a weighted plank when it's held for a duration instead of counted in sets.
    init(step: TimeSectionStep, context: ModelContext) {
        self.init(
            exercise: step.exercise,
            preferredEquipment: Binding(
                get: { step.preferredEquipment },
                set: { step.preferredEquipment = $0 }
            ),
            prefersBodyweight: Binding(
                get: { step.prefersBodyweight },
                set: { step.prefersBodyweight = $0 }
            ),
            onChange: {
                step.markDirty()
                try? context.save()
            }
        )
    }
}
