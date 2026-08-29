import SwiftUI
import SwiftData

struct EquipmentDetailView: View {
    @Bindable var equipment: Equipment
    @Environment(\.modelContext) private var context
    @State private var newWeightText = ""
    @State private var expandedLevelID: UUID?
    @State private var showingDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // The green band carries the name, so the flags are the first thing under it.
            Section {
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
                // Same gutter the sections below use, rather than centred against them —
                // narrower than a text row's because each chip carries its own padding.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HeaderMetrics.chipGutter)
                .padding(.vertical, 10)
                .fullBleedRow()
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .fullBleedRow()
                }

                if equipment.isLevelBased {
                    Section {
                        ForEach(equipment.sortedWeightCombos) { combo in
                            levelRow(combo)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .fullBleedRow(isLast: false)
                        }
                        .onDelete(perform: deleteWeightCombos)

                        Button("Add Level") { addLevel() }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .fullBleedRow()
                    } header: {
                        Text("Levels")
                    } footer: {
                        Text("Levels number automatically. Tap one to give it an optional name and color.")
                    }
                } else {
                    Section("Available weights") {
                        ForEach(equipment.sortedWeightCombos) { combo in
                            Text(formatted(combo.value))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .fullBleedRow(isLast: false)
                        }
                        .onDelete(perform: deleteWeightCombos)

                        HStack {
                            TextField("Add weight", text: $newWeightText)
                                .keyboardType(.decimalPad)
                            Button("Add") { addWeightCombo() }
                                .disabled(Double(newWeightText) == nil)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .fullBleedRow()
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
                Button {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Equipment", systemImage: "trash")
                        .foregroundStyle(deleteBlockReason == nil ? Color.appDanger : Color.appInkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        // The tint is what keeps it reading as set apart now that every
                        // row is one continuous white band — same treatment as Settings'
                        // Danger Zone.
                        .background((deleteBlockReason == nil ? Color.appDanger : Color.clear).opacity(0.06))
                }
                .buttonStyle(.plain)
                .disabled(deleteBlockReason != nil)
                .fullBleedRow()
            } header: {
                FormSectionHeader("Danger Zone")
            } footer: {
                // Says which reference is holding it, rather than leaving a dead button
                // to be puzzled over.
                FormSectionFooter(deleteBlockReason ?? "Nothing references this equipment, so it can be removed from your library.")
            }
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) { PushedTitleBand(title: equipment.name) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete \"\(equipment.name)\"?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteThis() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes it from your library. Anything that already referenced it would have blocked this.")
        }
        .alert("Can't Delete", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private var deleteBlockReason: String? {
        CatalogDeletionService.deletionBlockReason(for: equipment)
    }

    private func deleteThis() {
        do {
            try CatalogDeletionService.delete(equipment, context: context)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
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
