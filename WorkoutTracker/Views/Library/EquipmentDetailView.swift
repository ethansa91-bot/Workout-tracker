import SwiftUI
import SwiftData

struct EquipmentDetailView: View {
    @Bindable var equipment: Equipment
    @Environment(\.modelContext) private var context
    @State private var newWeightText = ""

    var body: some View {
        List {
            Section {
                DetailHeader(
                    systemName: equipment.iconSymbolName,
                    title: equipment.name,
                    subtitle: equipment.isCustom ? "Custom equipment" : nil
                )

                Toggle("In my equipment", isOn: Binding(
                    get: { equipment.isFavorited },
                    set: { newValue in
                        equipment.isFavorited = newValue
                        equipment.markDirty()
                        try? context.save()
                    }
                ))
            }

            if equipment.isFavorited {
                Section("Available weights") {
                    ForEach(equipment.sortedWeightCombos) { combo in
                        Text(formatted(combo.value))
                    }
                    .onDelete(perform: deleteWeightCombos)

                    HStack {
                        TextField("Add weight", text: $newWeightText)
                            .keyboardType(.decimalPad)
                        Button("Add") { addWeightCombo() }
                            .disabled(Double(newWeightText) == nil)
                    }
                }
            } else {
                Section {
                    Text("Add to your equipment to personalize its available weights.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Sync")
                    Spacer()
                    SyncButton(isDirty: equipment.isDirty) {
                        try? await SyncEngine.shared.syncSingle(equipment: equipment)
                    }
                }
            }
        }
        .themedListBackground()
        .navigationTitle(equipment.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatted(_ value: Double) -> String {
        let unit = AppSettings.weightUnit
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value)) \(unit)"
            : "\(value) \(unit)"
    }

    private func addWeightCombo() {
        guard let value = Double(newWeightText) else { return }
        let nextOrder = (equipment.weightCombos.map(\.sortOrder).max() ?? -1) + 1
        let combo = WeightCombo(equipment: equipment, value: value, sortOrder: nextOrder)
        context.insert(combo)
        equipment.markDirty()
        try? context.save()
        newWeightText = ""
    }

    private func deleteWeightCombos(at offsets: IndexSet) {
        let combos = equipment.sortedWeightCombos
        for index in offsets {
            SyncDeletion.delete(combos[index], context: context)
        }
        equipment.markDirty()
        try? context.save()
    }
}
