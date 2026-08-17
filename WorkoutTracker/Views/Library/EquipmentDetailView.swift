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
                .listRowSeparator(.hidden)

                HStack(spacing: 8) {
                    SelectableChip(icon: "house", title: "At Home", isSelected: equipment.isAtHome, tint: Color.accentColor) {
                        toggleHome()
                    }
                    SelectableChip(icon: "building.2", title: "At Gym", isSelected: equipment.isAtGym, tint: .orange) {
                        toggleGym()
                    }
                    SelectableChip(icon: "dumbbell", title: "Weighted", isSelected: equipment.isWeighted, tint: Color.appRust) {
                        toggleWeighted()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)
            }

            if equipment.isWeighted {
                Section("Weight Unit") {
                    Picker("Weight unit", selection: Binding(
                        get: { equipment.effectiveWeightUnit },
                        set: { newValue in
                            equipment.preferredWeightUnit = newValue
                            equipment.markDirty()
                            try? context.save()
                        }
                    )) {
                        Text("kg").tag("kg")
                        Text("lb").tag("lb")
                    }
                    .pickerStyle(.segmented)
                }

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
                    Text("Turn on Weighted to add available weights and a unit for this equipment.")
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

    private func toggleHome() {
        equipment.isAtHome.toggle()
        equipment.markDirty()
        try? context.save()
    }

    private func toggleGym() {
        equipment.isAtGym.toggle()
        equipment.markDirty()
        try? context.save()
    }

    private func toggleWeighted() {
        equipment.isWeighted.toggle()
        equipment.markDirty()
        try? context.save()
    }

    private func formatted(_ value: Double) -> String {
        let unit = equipment.effectiveWeightUnit
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
