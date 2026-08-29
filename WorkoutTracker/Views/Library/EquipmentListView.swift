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
        // Read once, not once per row — reading `.last?.id` inside the `ForEach` re-ran
        // the filter for every row.
        //
        // Split on the stored `isWeighted` flag, the same predicate the exercise forms
        // use: the two kinds are barely comparable — one carries adjustable load and has
        // weight settings behind it, the other is a mat or a bench — so a single
        // alphabetical run interleaved them for no reason. Both halves still come out of
        // `filtered`, so search and the Home/Gym chips narrow them together.
        let items = filtered
        let weighted = items.filter(\.isWeighted)
        let other = items.filter { !$0.isWeighted }

        List {
            if !weighted.isEmpty {
                section("Weighted Equipment", weighted)
            }
            if !other.isEmpty {
                section("Other Equipment", other)
            }
        }
        .fullBleedList()
        // The first band sits directly under the filter chips, where a plain list's own
        // top inset would otherwise leave a strip of ground between the two.
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PushedTitleBand(title: "Equipment")
                InlineSearchField(prompt: "Search equipment", text: $searchText)
                HStack(spacing: 12) {
                    filterChip(icon: "house", label: "At Home", isOn: homeOnly, tint: Color.accentColor) {
                        homeOnly.toggle()
                    }
                    filterChip(icon: "building.2", label: "At the Gym", isOn: gymOnly, tint: .orange) {
                        gymOnly.toggle()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.appSurface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.appHairline)
                        .frame(height: 0.5)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    /// One banded group. Position and `isLast` are both taken from this section's own
    /// array — `fullBleedRow(isLast:)` closes off a group rather than the whole list, and
    /// the numbers read as "position within this kind", restarting at 1 in each.
    private func section(_ title: String, _ items: [Equipment]) -> some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, equipment in
                NavigationLink {
                    EquipmentDetailView(equipment: equipment)
                } label: {
                    equipmentRow(equipment, position: index + 1)
                }
                .fullBleedRow(isLast: equipment.id == items.last?.id)
            }
        } header: {
            ListBandHeader(title: title)
        }
    }

    private func equipmentRow(_ equipment: Equipment, position: Int) -> some View {
        HStack(spacing: 12) {
            // A position rather than the item's own symbol, which was close to arbitrary.
            // `size: 34` is what `IconBadge` used, so the row keeps its metrics.
            NumberBadge(number: position, size: 34)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
