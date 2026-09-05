import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    /// Sheeted from the workout builder rather than pushed from the Library. Wraps the
    /// page in its own `NavigationStack` — `PushedTitleBand` is sized to sit under a real
    /// navigation bar, and without one it butts against the sheet's top edge — and adds
    /// the Done that a sheet has no back chevron to replace. `AddPersonalRecordSheet`
    /// carries the same two jobs for the same reason, under its own `NavigationStack`.
    var isPresentedAsSheet: Bool = false
    @Environment(\.modelContext) private var context
    @State private var showingEdit = false
    @State private var showingVideoPlayer = false
    @State private var showingPicturePreview = false
    @State private var showingDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \ExerciseCategory.name) private var allCategories: [ExerciseCategory]

    var body: some View {
        if isPresentedAsSheet {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            // Name, notes and the edit button all live in the green band now, so the
            // first thing under it is the exercise's own content.
            Section {
                if hasPicture {
                    pictureRow
                }

                if let videoURL = exercise.videoURL, YouTubeURL.videoID(from: videoURL) != nil {
                    videoButton
                }

                favoriteRow
            }

            Section {
                chipGrid(allMuscles, tint: .appAccent, title: \.name, isSelected: isMuscleSelected, toggle: toggleMuscle)
            } header: {
                ListBandHeader(title: "Muscles")
            }

            Section {
                chipGrid(allEquipment.filter { !$0.isWeighted }, tint: .appStepBrown, title: \.name, isSelected: isEquipmentSelected, toggle: toggleEquipment)
            } header: {
                ListBandHeader(title: "Passive Equipment")
            }

            Section {
                defaultEquipmentRow
                chipGrid(allEquipment.filter { $0.isWeighted }, tint: .appStepBlue, title: \.name, isSelected: isEquipmentSelected, toggle: toggleEquipment)
            } header: {
                // On the band rather than as a chip among the equipment: it qualifies the
                // whole section — "this can also be done unloaded" — instead of being one
                // more thing to attach. It also gets the chip out of `SelectableChip`'s
                // `.fill` icon swap, which had no symbol to resolve to.
                ListBandHeader(title: "Weighted Equipment") {
                    if exercise.weightedEquipment != nil {
                        BandToggleButton(text: "Allow bodyweight", isOn: exercise.allowsBodyweight) {
                            toggleFlag { exercise.allowsBodyweight.toggle() }
                        }
                    }
                }
            }

            Section {
                chipGrid(allCategories, tint: .appRust, title: { $0.name.capitalized }, isSelected: isCategorySelected, toggle: toggleCategory)
            } header: {
                ListBandHeader(title: "Categories")
            }

            ExecutionTypeChipSection(
                isSelected: isExecutionTypeSelected,
                toggle: toggleExecutionType,
                onCreate: toggleExecutionType,
                selectedCount: exercise.sortedExecutionTypes.count,
                separateRecords: Binding(
                    get: { exercise.separateRecordsPerExecutionType },
                    set: { newValue in toggleFlag { exercise.separateRecordsPerExecutionType = newValue } }
                )
            )

            ProgressionSection(exercise: exercise, context: context)

            Section {
                Button {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Exercise", systemImage: "trash")
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
                FormSectionFooter(deleteBlockReason ?? "Nothing references this exercise, so it can be removed from your library.")
            }

        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(title: exercise.displayName, subtitle: exercise.notes) {
                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedAsSheet {
                // "Done", not "Cancel": every control on this page writes through as it's
                // touched, so by the time this is tapped the work is already saved.
                ToolbarItem(placement: .cancellationAction) {
                    // A glyph, not "Done": the text button rendered blank often enough to
                    // look broken, and a tick reads the same at a glance.
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .alert("Delete \"\(exercise.displayName)\"?", isPresented: $showingDeleteConfirm) {
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
        .sheet(isPresented: $showingEdit) {
            ExerciseIdentityEditView(exercise: exercise)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let videoURL = exercise.videoURL, let videoID = YouTubeURL.videoID(from: videoURL) {
                NavigationStack {
                    YouTubePlayerView(videoID: videoID, maxSeconds: nil, muted: false, showsControls: true)
                        .navigationTitle(exercise.displayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingVideoPlayer = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingPicturePreview) {
            NavigationStack {
                fullPicture
                    .navigationTitle(exercise.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingPicturePreview = false }
                        }
                    }
            }
        }
    }

    // MARK: - Header pieces

    /// Only an actual picture — an uploaded/generated image or a bundled catalog asset.
    /// `nil` when there isn't one, rather than a placeholder box.
    @ViewBuilder
    private func pictureImage(fill: Bool) -> some View {
        if let fileName = exercise.generatedImageFileName, let uiImage = GeneratedExerciseImageStore.load(fileName: fileName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: fill ? .fill : .fit)
        } else if let assetName = exercise.imageAssetName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: fill ? .fill : .fit)
        }
    }

    private var hasPicture: Bool {
        exercise.generatedImageFileName != nil || exercise.imageAssetName != nil
    }

    /// Same idea as `videoButton` — a compact row (not a big hero image), tap to open
    /// the full picture in a sheet — but with a small thumbnail of the actual picture
    /// on the right instead of a generic icon, since there's a real image to preview.
    private var pictureRow: some View {
        Button {
            showingPicturePreview = true
        } label: {
            HStack(spacing: 8) {
                Text("Photo")
                    .foregroundStyle(Color.appInkMuted)
                Spacer()
                pictureImage(fill: true)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
    }

    private var fullPicture: some View {
        pictureImage(fill: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    /// A compact button (not a big thumbnail) that opens the video in an in-app sheet —
    /// the picture area above is for photos only now.
    private var videoButton: some View {
        Button {
            showingVideoPlayer = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.appDanger)
                Text("YouTube Video")
                    .foregroundStyle(Color.appDanger)
            }
        }
        .buttonStyle(.plain)
    }

    /// Favorite, and the one capability flag that isn't tied to a section below.
    /// "Allow bodyweight" used to live here too; it now qualifies the Weighted Equipment
    /// band, which is the thing it actually depends on.
    private var favoriteRow: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            SelectableChip(icon: "star", title: "Favorite", isSelected: exercise.isFavorited, tint: Color.appStepYellow) {
                toggleFlag { exercise.isFavorited.toggle() }
            }
            // No icon: `SelectableChip` appends `.fill` when selected, and
            // `arrow.left.and.right.fill` is not a symbol — so the chip rendered blank
            // exactly when it was on.
            SelectableChip(title: "One-sided", isSelected: exercise.isOneSided, tint: Color.appStepBrown) {
                toggleFlag { exercise.isOneSided.toggle() }
            }
        }
        // Same gutter as `chipGrid`, so the flag chips and the muscle/equipment chips
        // start and end on one line rather than one being centred against the other.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HeaderMetrics.chipGutter)
        .padding(.vertical, 10)
    }


    private var deleteBlockReason: String? {
        CatalogDeletionService.deletionBlockReason(for: exercise)
    }

    private func deleteThis() {
        do {
            try CatalogDeletionService.delete(exercise, context: context)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    /// Which weighted item — or bodyweight — this exercise means when a workout doesn't
    /// say. The same control the workout builder's own Equipment picker uses, because it is
    /// the same question one level up: whatever is chosen here is what that picker opens on.
    ///
    /// Offered only when there is more than one answer, which is the rule that picker
    /// applies too.
    @ViewBuilder
    private var defaultEquipmentRow: some View {
        if exercise.hasEquipmentChoice {
            SettingMenu(
                title: "Default equipment",
                // The tint this section's chips already carry, so the value reads as part
                // of Weighted Equipment rather than importing the popover's rust.
                value: exercise.defaultWeightedEquipment?.name ?? "Bodyweight",
                valueColor: Color.appStepBlue,
                hugsTitle: true
            ) {
                ForEach(exercise.weightedEquipmentOptions) { item in
                    Button(item.name) {
                        toggleFlag {
                            exercise.defaultsToBodyweight = false
                            exercise.defaultEquipmentName = item.name
                        }
                    }
                }
                if exercise.allowsBodyweightSource {
                    Button("Bodyweight") {
                        toggleFlag {
                            exercise.defaultsToBodyweight = true
                            exercise.defaultEquipmentName = nil
                        }
                    }
                }
            }
            .formRow(isLast: false)
        }
    }

    private func toggleFlag(_ change: () -> Void) {
        change()
        exercise.markDirty()
        try? context.save()
    }

    // MARK: - Chip sections

    private func chipGrid<Item: Identifiable>(
        _ items: [Item],
        tint: Color,
        title: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        toggle: @escaping (Item) -> Void
    ) -> some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(items) { item in
                SelectableChip(title: title(item), isSelected: isSelected(item), tint: tint) {
                    toggle(item)
                }
            }
        }
        // Narrower than the 16pt other rows use, because a chip carries 10pt of its own
        // horizontal padding — at a full 16 the chip's *text* started 10pt right of the
        // section title above it. This lands the capsule's edge on the shared gutter.
        .padding(.horizontal, HeaderMetrics.chipGutter)
        .padding(.vertical, 10)
    }

    private func isMuscleSelected(_ muscle: Muscle) -> Bool {
        exercise.muscles.contains { $0.id == muscle.id }
    }

    private func toggleMuscle(_ muscle: Muscle) {
        if let index = exercise.muscles.firstIndex(where: { $0.id == muscle.id }) {
            exercise.muscles.remove(at: index)
        } else {
            exercise.muscles.append(muscle)
        }
        exercise.markDirty()
        try? context.save()
    }

    private func isEquipmentSelected(_ equipment: Equipment) -> Bool {
        exercise.equipmentItems.contains { $0.id == equipment.id }
    }

    private func toggleEquipment(_ equipment: Equipment) {
        if let index = exercise.equipmentItems.firstIndex(where: { $0.id == equipment.id }) {
            exercise.equipmentItems.remove(at: index)
        } else {
            exercise.equipmentItems.append(equipment)
        }
        exercise.markDirty()
        try? context.save()
    }

    private func isExecutionTypeSelected(_ type: ExecutionType) -> Bool {
        exercise.executionTypes.contains { $0.id == type.id }
    }

    private func toggleExecutionType(_ type: ExecutionType) {
        if let index = exercise.executionTypes.firstIndex(where: { $0.id == type.id }) {
            exercise.executionTypes.remove(at: index)
        } else {
            exercise.executionTypes.append(type)
        }
        exercise.markDirty()
        try? context.save()
    }

    private func isCategorySelected(_ category: ExerciseCategory) -> Bool {
        exercise.categories.contains { $0.id == category.id }
    }

    private func toggleCategory(_ category: ExerciseCategory) {
        if let index = exercise.categories.firstIndex(where: { $0.id == category.id }) {
            exercise.categories.remove(at: index)
        } else {
            exercise.categories.append(category)
        }
        exercise.markDirty()
        try? context.save()
    }
}
