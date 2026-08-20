import SwiftUI
import SwiftData

struct EquipmentDetailView: View {
    @Bindable var equipment: Equipment
    @Environment(\.modelContext) private var context
    @State private var newWeightText = ""
    @State private var expandedLevelID: UUID?

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
                        Text("Level").tag(Equipment.levelUnit)
                    }
                    .pickerStyle(.segmented)
                }

                if equipment.isLevelBased {
                    Section {
                        ForEach(equipment.sortedWeightCombos) { combo in
                            levelRow(combo)
                        }
                        .onDelete(perform: deleteWeightCombos)

                        Button("Add Level") { addLevel() }
                    } header: {
                        Text("Levels")
                    } footer: {
                        Text("Levels number automatically. Tap one to give it an optional name and color.")
                    }
                } else {
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
                }
            } else {
                Section {
                    Text("Turn on Weighted to add available weights and a unit for this equipment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    /// Tap to expand in place — same accordion idea used elsewhere in this app
    /// (e.g. follow-along step rows) — revealing an optional label + color editor.
    private func levelRow(_ combo: WeightCombo) -> some View {
        let isExpanded = expandedLevelID == combo.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let color = combo.color {
                    Circle().fill(color.color).frame(width: 12, height: 12)
                }
                Text(combo.levelDisplayName)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { expandedLevelID = isExpanded ? nil : combo.id }
            }

            if isExpanded {
                levelEditor(combo)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 2)
    }

    private func levelEditor(_ combo: WeightCombo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Optional name", text: Binding(
                get: { combo.label ?? "" },
                set: { newValue in
                    combo.label = newValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newValue
                    saveLevel(combo)
                }
            ))
            .textFieldStyle(.roundedBorder)

            PaletteColorPicker(selection: Binding(
                get: { combo.color },
                set: { combo.color = $0; saveLevel(combo) }
            ), swatchSize: 24)
        }
        .padding(.leading, 20)
    }

    private func saveLevel(_ combo: WeightCombo) {
        combo.markDirty()
        try? context.save()
    }

    private func addLevel() {
        let nextOrder = (equipment.weightCombos.map(\.sortOrder).max() ?? -1) + 1
        let combo = WeightCombo(equipment: equipment, value: equipment.nextLevelValue, sortOrder: nextOrder)
        context.insert(combo)
        equipment.markDirty()
        try? context.save()
    }
}
