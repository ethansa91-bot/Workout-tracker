import SwiftUI
import SwiftData

struct EquipmentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]

    @State private var searchText = ""
    @State private var favoritedOnly = false
    @State private var showingCreateSheet = false

    private var filtered: [Equipment] {
        allEquipment.filter { equipment in
            equipment.deletedAt == nil
                && (searchText.isEmpty || equipment.name.localizedCaseInsensitiveContains(searchText))
                && (!favoritedOnly || equipment.isFavorited)
        }
    }

    var body: some View {
        List {
            Toggle("My equipment only", isOn: $favoritedOnly)

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
                toggleFavorite(equipment)
            } label: {
                Image(systemName: equipment.isFavorited ? "star.fill" : "star")
                    .foregroundStyle(equipment.isFavorited ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func toggleFavorite(_ equipment: Equipment) {
        equipment.isFavorited.toggle()
        equipment.markDirty()
        try? context.save()
    }
}
