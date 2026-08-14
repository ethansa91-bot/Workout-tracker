import SwiftUI
import SwiftData

/// Creating custom equipment marks it "At Home", so the weight-combo editor is inline
/// here rather than requiring a separate trip to the detail view afterward.
struct CustomEquipmentFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var weightUnit = AppSettings.weightUnit
    @State private var weightValues: [Double] = []
    @State private var newWeightText = ""
    @State private var createdEquipment: Equipment?

    var body: some View {
        NavigationStack {
            if let createdEquipment {
                PostSaveSyncPrompt(
                    itemName: createdEquipment.name,
                    model: createdEquipment,
                    syncSingle: { try? await SyncEngine.shared.syncSingle(equipment: createdEquipment) },
                    onDone: { dismiss() }
                )
            } else {
                Form {
                    Section("Name") {
                        TextField("e.g. Adjustable Dumbbells", text: $name)
                    }
                    Section("Weight Unit") {
                        Picker("Weight unit", selection: $weightUnit) {
                            Text("kg").tag("kg")
                            Text("lb").tag("lb")
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Available weights") {
                        ForEach(weightValues.indices, id: \.self) { index in
                            Text(formatted(weightValues[index]))
                        }
                        .onDelete { weightValues.remove(atOffsets: $0) }

                        HStack {
                            TextField("Add weight", text: $newWeightText)
                                .keyboardType(.decimalPad)
                            Button("Add") {
                                if let value = Double(newWeightText) {
                                    weightValues.append(value)
                                    newWeightText = ""
                                }
                            }
                            .disabled(Double(newWeightText) == nil)
                        }
                    }
                }
                .themedListBackground()
                .navigationTitle("New Equipment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value)) \(weightUnit)"
            : "\(value) \(weightUnit)"
    }

    private func save() {
        let equipment = Equipment(
            name: name.trimmingCharacters(in: .whitespaces),
            iconSymbolName: IconSymbolMapping.defaultEquipmentSymbol,
            isCustom: true,
            isAtHome: true,
            preferredWeightUnit: weightUnit
        )
        context.insert(equipment)
        for (index, value) in weightValues.enumerated() {
            let combo = WeightCombo(equipment: equipment, value: value, sortOrder: index)
            context.insert(combo)
        }
        try? context.save()
        createdEquipment = equipment
    }
}
