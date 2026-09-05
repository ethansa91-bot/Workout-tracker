import SwiftUI
import SwiftData

struct MuscleListView: View {
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \MuscleCategory.name) private var categories: [MuscleCategory]

    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var showingCreateSheet = false

    private var filteredMuscles: [Muscle] {
        allMuscles.filter { muscle in
            muscle.deletedAt == nil
                && (searchText.isEmpty || muscle.name.localizedCaseInsensitiveContains(searchText))
                && (selectedCategory == nil || muscle.categories.contains { $0.name == selectedCategory })
        }
    }

    var body: some View {
        // Read once, not once per row — the filter walks each muscle's `categories`
        // relationship, and reading `.last?.id` inside the `ForEach` re-ran it per row.
        let muscles = filteredMuscles
        let lastID = muscles.last?.id

        List {
            ForEach(muscles) { muscle in
                NavigationLink {
                    MuscleEditView(muscle: muscle)
                } label: {
                    muscleRow(muscle)
                }
                .fullBleedRow(isLast: muscle.id == lastID)
            }
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                PushedTitleBand(title: "Muscles")
                InlineSearchField(prompt: "Search muscles", text: $searchText)
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(String?.none)
                    ForEach(categories) { category in
                        Text(category.name.capitalized).tag(Optional(category.name))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
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
            NavigationStack { MuscleEditView(muscle: nil) }
        }
    }

    private func muscleRow(_ muscle: Muscle) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: muscle.iconSymbolName)
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.name)
                Text(muscle.categories.map { $0.name.capitalized }.sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Edit a muscle's name and category tags — reached directly by tapping it in the list,
/// no read-only detail screen in between. Deliberately doesn't show the exercises that
/// target this muscle; that list isn't useful here and was removed.
/// Edits an existing muscle, or creates one when `muscle` is nil — the name field and
/// the category picker (with its inline "add category") are the same either way, so this
/// takes an optional rather than there being a second, near-identical form.
struct MuscleEditView: View {
    let muscle: Muscle?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MuscleCategory.name) private var allCategories: [MuscleCategory]

    @State private var name: String
    @State private var selectedCategoryIDs: Set<UUID>
    @State private var newCategoryName = ""
    /// Categories created this session — merged with `allCategories` when saving so the
    /// final selection is correct even if `@Query` hasn't refreshed yet by the time
    /// `save()` runs.
    @State private var createdCategories: [MuscleCategory] = []

    init(muscle: Muscle?) {
        self.muscle = muscle
        _name = State(initialValue: muscle?.name ?? "")
        _selectedCategoryIDs = State(initialValue: Set(muscle?.categories.map(\.id) ?? []))
    }

    var body: some View {
        List {
            Section {
                TextField("Muscle name", text: $name)
                    .formRow()
            } header: {
                ListBandHeader(title: "Name")
            }

            Section {
                let categories = allCategories + createdCategories.filter { created in
                    !allCategories.contains { $0.id == created.id }
                }
                ForEach(categories) { category in
                    Toggle(category.name.capitalized, isOn: Binding(
                        get: { selectedCategoryIDs.contains(category.id) },
                        set: { isOn in
                            if isOn { selectedCategoryIDs.insert(category.id) }
                            else { selectedCategoryIDs.remove(category.id) }
                        }
                    ))
                    .tint(Color.appAccent)
                    .formRow(isLast: false)
                }
                HStack {
                    TextField("New category", text: $newCategoryName)
                    Button("Add") { addNewCategory() }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .formRow()
            } header: {
                ListBandHeader(title: "Categories")
            }
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(title: muscle == nil ? "New Muscle" : "Edit Muscle")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Creating is presented as a sheet, which has no back button of its own.
            if muscle == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = (allCategories + createdCategories).first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedCategoryIDs.insert(existing.id)
        } else {
            let category = MuscleCategory(name: trimmed)
            context.insert(category)
            createdCategories.append(category)
            selectedCategoryIDs.insert(category.id)
        }
        newCategoryName = ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Inserted only here, so backing out of the form leaves nothing behind.
        let target = muscle ?? {
            let created = Muscle(name: trimmed, iconSymbolName: IconSymbolMapping.defaultMuscleSymbol)
            context.insert(created)
            return created
        }()
        target.name = trimmed
        let available = allCategories + createdCategories.filter { created in !allCategories.contains { $0.id == created.id } }
        target.categories = available.filter { selectedCategoryIDs.contains($0.id) }
        target.markDirty()
        try? context.save()
        dismiss()
    }
}
