import SwiftUI
import SwiftData

struct EquipmentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    @State private var searchText = ""
    @State private var homeOnly = false
    @State private var gymOnly = false
    @State private var showingCreateSheet = false

    private var filtered: [Equipment] {
        allEquipment.filter { equipment in
            equipment.deletedAt == nil
                && (searchText.isEmpty || equipment.name.localizedCaseInsensitiveContains(searchText))
                && (!homeOnly || equipment.isAtHome)
                && (!gymOnly || equipment.isAtGym)
        }
    }

    var body: some View {
        List {
            HStack(spacing: 12) {
                filterChip(icon: "house", label: "At Home", isOn: homeOnly, tint: Color.accentColor) {
                    homeOnly.toggle()
                }
                filterChip(icon: "building.2", label: "At the Gym", isOn: gymOnly, tint: .orange) {
                    gymOnly.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
            .padding(.vertical, 4)

            ForEach(filtered) { equipment in
                NavigationLink {
                    EquipmentDetailView(equipment: equipment)
                } label: {
                    equipmentRow(equipment)
                }
            }
        }
        .themedListBackground()
        .searchable(text: $searchText, prompt: "Search equipment")
        .navigationTitle("Equipment")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CustomEquipmentFormView()
        }
    }

    private func equipmentRow(_ equipment: Equipment) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: equipment.iconSymbolName)
            VStack(alignment: .leading, spacing: 3) {
                Text(equipment.name)
                if equipment.isCustom {
                    StatusPill(text: "Custom", tint: .accentColor)
                }
            }
            Spacer()
            Button {
                toggleHome(equipment)
            } label: {
                Image(systemName: equipment.isAtHome ? "house.fill" : "house")
                    .foregroundStyle(equipment.isAtHome ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            Button {
                toggleGym(equipment)
            } label: {
                Image(systemName: equipment.isAtGym ? "building.2.fill" : "building.2")
                    .foregroundStyle(equipment.isAtGym ? .orange : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    /// The list-level filter toggle — capsule chip style matching
    /// `ExerciseQuickFilterView`'s quick filters, used here to activate/deactivate
    /// filtering by home/gym rather than to tag an individual equipment item (that's
    /// the plain icon buttons in `equipmentRow` instead).
    private func filterChip(icon: String, label: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: isOn ? "\(icon).fill" : icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? Color.white : tint)
                .background(isOn ? tint : tint.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.clear : tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toggleHome(_ equipment: Equipment) {
        equipment.isAtHome.toggle()
        equipment.markDirty()
        try? context.save()
    }

    private func toggleGym(_ equipment: Equipment) {
        equipment.isAtGym.toggle()
        equipment.markDirty()
        try? context.save()
    }
}
