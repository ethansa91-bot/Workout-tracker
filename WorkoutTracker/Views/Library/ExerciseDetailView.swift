import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @State private var showingEdit = false
    @State private var notesExpanded = false
    @State private var showingVideoPlayer = false
    @State private var showingPicturePreview = false

    @Query(sort: \Equipment.name) private var allEquipment: [Equipment]
    @Query(sort: \Muscle.name) private var allMuscles: [Muscle]
    @Query(sort: \ExerciseCategory.name) private var allCategories: [ExerciseCategory]

    var body: some View {
        List {
            Section {
                // One row (not two) for header + note — no row separator between them
                // and tight spacing, so the note reads as another field belonging with
                // the name rather than a visually distinct block.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        DetailHeader(
                            systemName: exercise.iconSymbolName,
                            title: exercise.displayName,
                            subtitle: exercise.showsSecondaryName ? exercise.name : (exercise.isCustom ? "Custom exercise" : nil)
                        )
                        Spacer()
                        Button {
                            showingEdit = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appInkMuted)
                    }

                    if let notes = exercise.notes, !notes.isEmpty {
                        notesPreview(notes)
                    }
                }

                if hasPicture {
                    pictureRow
                }

                if let videoURL = exercise.videoURL, YouTubeURL.videoID(from: videoURL) != nil {
                    videoButton
                }

                favoriteRow
            }

            Section("Muscles") {
                chipGrid(allMuscles, tint: .appAccent, title: \.name, isSelected: isMuscleSelected, toggle: toggleMuscle)
            }

            Section("Passive Equipment") {
                chipGrid(allEquipment.filter { !$0.isWeighted }, tint: .appStepBrown, title: \.name, isSelected: isEquipmentSelected, toggle: toggleEquipment)
            }

            Section("Weighted Equipment") {
                chipGrid(allEquipment.filter { $0.isWeighted }, tint: .appStepBlue, title: \.name, isSelected: isEquipmentSelected, toggle: toggleEquipment)
            }

            Section("Categories") {
                chipGrid(allCategories, tint: .appRust, title: { $0.name.capitalized }, isSelected: isCategorySelected, toggle: toggleCategory)
            }

        }
        .themedListBackground()
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
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

    /// Favorite plus the two capability flags that unlock per-workout options. The
    /// bodyweight chip only appears for exercises that carry weighted equipment — an
    /// exercise with none is bodyweight already, so the flag would say nothing.
    private var favoriteRow: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            SelectableChip(icon: "star", title: "Favorite", isSelected: exercise.isFavorited, tint: Color.appStepYellow) {
                toggleFlag { exercise.isFavorited.toggle() }
            }
            if exercise.weightedEquipment != nil {
                SelectableChip(icon: "figure.strengthtraining.functional", title: "Bodyweight OK", isSelected: exercise.allowsBodyweight, tint: Color.appStepBlue) {
                    toggleFlag { exercise.allowsBodyweight.toggle() }
                }
            }
            SelectableChip(icon: "arrow.left.and.right", title: "One-sided", isSelected: exercise.isOneSided, tint: Color.appStepBrown) {
                toggleFlag { exercise.isOneSided.toggle() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func toggleFlag(_ change: () -> Void) {
        change()
        exercise.markDirty()
        try? context.save()
    }

    /// Truncated to one line, tap to expand in place — same accordion idea as
    /// `TimeSectionEditorView`'s step rows (rotating chevron, no navigation away).
    private func notesPreview(_ notes: String) -> some View {
        Button {
            withAnimation { notesExpanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(notesExpanded ? nil : 1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(notesExpanded ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
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
        .padding(.vertical, 4)
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
