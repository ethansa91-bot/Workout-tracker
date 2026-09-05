import SwiftUI
import SwiftData

/// Creating custom equipment marks it "At Home", so the weight-combo editor is inline
/// here rather than requiring a separate trip to the detail view afterward.
struct CustomEquipmentFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// A not-yet-persisted option — its number is implied by its position in `options`.
    private struct DraftOption: Identifiable {
        let id = UUID()
        var label: String?
        var color: PaletteColor?
    }

    @State private var name = ""
    @State private var isWeighted = false
    @State private var weightUnit = AppSettings.weightUnit
    @State private var weightValues: [Double] = []
    @State private var newWeightText = ""
    @State private var options: [DraftOption] = []
    @State private var expandedOptionID: UUID?

    private var usesOptions: Bool { weightUnit == Equipment.optionUnit }

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
                            Text("Option").tag(Equipment.optionUnit)
                        }
                        .pickerStyle(.segmented)
                    }
                    if usesOptions {
                        Section {
                            ForEach(options) { option in
                                optionRow(option)
                            }
                            .onDelete { options.remove(atOffsets: $0) }

                            Button("Add Option") {
                                options.append(DraftOption())
                            }
                        } header: {
                            Text("Options")
                        } footer: {
                            Text("Options number automatically. Tap one to give it an optional name and color.")
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

    private func optionRow(_ option: DraftOption) -> some View {
        let isExpanded = expandedOptionID == option.id
        let number = (options.firstIndex(where: { $0.id == option.id }) ?? 0) + 1
        let displayName = option.label?.isEmpty == false ? "\(number). \(option.label!)" : WeightCombo.optionDisplayName(for: Double(number))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let color = option.color {
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
                withAnimation { expandedOptionID = isExpanded ? nil : option.id }
            }

            if isExpanded {
                optionEditor(option)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 2)
    }

    private func optionEditor(_ option: DraftOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Optional name", text: Binding(
                get: { option.label ?? "" },
                set: { newValue in
                    guard let index = options.firstIndex(where: { $0.id == option.id }) else { return }
                    options[index].label = newValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newValue
                }
            ))
            .textFieldStyle(.roundedBorder)

            PaletteColorPicker(selection: Binding(
                get: { option.color },
                set: { newValue in
                    guard let index = options.firstIndex(where: { $0.id == option.id }) else { return }
                    options[index].color = newValue
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
            if usesOptions {
                for (index, option) in options.enumerated() {
                    let combo = WeightCombo(equipment: equipment, value: Double(index + 1), sortOrder: index, label: option.label, color: option.color)
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
