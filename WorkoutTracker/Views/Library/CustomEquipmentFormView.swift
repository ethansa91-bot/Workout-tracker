import SwiftUI
import SwiftData

/// Creating custom equipment marks it "At Home", so the weight-combo editor is inline
/// here rather than requiring a separate trip to the detail view afterward.
struct CustomEquipmentFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// A not-yet-persisted level — number is implied by its position in `levels`.
    private struct DraftLevel: Identifiable {
        let id = UUID()
        var label: String?
        var color: PaletteColor?
    }

    @State private var name = ""
    @State private var isWeighted = false
    @State private var weightUnit = AppSettings.weightUnit
    @State private var weightValues: [Double] = []
    @State private var newWeightText = ""
    @State private var levels: [DraftLevel] = []
    @State private var expandedLevelID: UUID?

    private var isLevelBased: Bool { weightUnit == Equipment.levelUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Adjustable Dumbbells", text: $name)
                }
                Section {
                    Toggle("Weighted", isOn: $isWeighted)
                } footer: {
                    Text(isWeighted
                        ? "Weighted equipment (dumbbells, vests) can have available weights and a unit."
                        : "Passive equipment (mats, benches, rings) has no adjustable weight.")
                }
                if isWeighted {
                    Section("Weight Unit") {
                        Picker("Weight unit", selection: $weightUnit) {
                            Text("kg").tag("kg")
                            Text("lb").tag("lb")
                            Text("Level").tag(Equipment.levelUnit)
                        }
                        .pickerStyle(.segmented)
                    }
                    if isLevelBased {
                        Section {
                            ForEach(levels) { level in
                                levelRow(level)
                            }
                            .onDelete { levels.remove(atOffsets: $0) }

                            Button("Add Level") {
                                levels.append(DraftLevel())
                            }
                        } header: {
                            Text("Levels")
                        } footer: {
                            Text("Levels number automatically. Tap one to give it an optional name and color.")
                        }
                    } else {
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

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value)) \(weightUnit)"
            : "\(value) \(weightUnit)"
    }

    private func levelRow(_ level: DraftLevel) -> some View {
        let isExpanded = expandedLevelID == level.id
        let number = (levels.firstIndex(where: { $0.id == level.id }) ?? 0) + 1
        let displayName = level.label?.isEmpty == false ? level.label! : "Level \(number)"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let color = level.color {
                    Circle().fill(color.color).frame(width: 12, height: 12)
                }
                Text(displayName)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { expandedLevelID = isExpanded ? nil : level.id }
            }

            if isExpanded {
                levelEditor(level)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 2)
    }

    private func levelEditor(_ level: DraftLevel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Optional name", text: Binding(
                get: { level.label ?? "" },
                set: { newValue in
                    guard let index = levels.firstIndex(where: { $0.id == level.id }) else { return }
                    levels[index].label = newValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newValue
                }
            ))
            .textFieldStyle(.roundedBorder)

            PaletteColorPicker(selection: Binding(
                get: { level.color },
                set: { newValue in
                    guard let index = levels.firstIndex(where: { $0.id == level.id }) else { return }
                    levels[index].color = newValue
                }
            ), swatchSize: 24)
        }
        .padding(.leading, 20)
    }

    private func save() {
        let equipment = Equipment(
            name: name.trimmingCharacters(in: .whitespaces),
            iconSymbolName: IconSymbolMapping.defaultEquipmentSymbol,
            isCustom: true,
            isAtHome: true,
            isWeighted: isWeighted,
            preferredWeightUnit: isWeighted ? weightUnit : nil
        )
        context.insert(equipment)
        if isWeighted {
            if isLevelBased {
                for (index, level) in levels.enumerated() {
                    let combo = WeightCombo(equipment: equipment, value: Double(index + 1), sortOrder: index, label: level.label, color: level.color)
                    context.insert(combo)
                }
            } else {
                for (index, value) in weightValues.enumerated() {
                    let combo = WeightCombo(equipment: equipment, value: value, sortOrder: index)
                    context.insert(combo)
                }
            }
        }
        try? context.save()
        dismiss()
    }
}
