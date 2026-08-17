import SwiftUI
import SwiftData
import PhotosUI

/// Edits just an existing exercise's textual identity fields — name, personal label,
/// photo, YouTube link, and notes. Reached via the pencil next to the name on
/// `ExerciseDetailView`. Equipment/muscle/category and Favorite are edited directly on
/// the detail page itself now, not here — see `ExerciseDetailView`'s chip sections.
struct ExerciseIdentityEditView: View {
    @Bindable var exercise: Exercise

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var label: String
    @State private var notes: String
    @State private var videoURLText: String

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var pendingPhotoRemoved = false

    init(exercise: Exercise) {
        self.exercise = exercise
        _name = State(initialValue: exercise.name)
        _label = State(initialValue: exercise.label ?? "")
        _notes = State(initialValue: exercise.notes ?? "")
        _videoURLText = State(initialValue: exercise.videoURL ?? "")
    }

    private var currentPhoto: UIImage? {
        guard let fileName = exercise.generatedImageFileName else { return nil }
        return GeneratedExerciseImageStore.load(fileName: fileName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Cable Chest Fly", text: $name)
                }

                Section {
                    TextField("e.g. Front squat (heavy)", text: $label)
                } header: {
                    Text("Personal Label")
                } footer: {
                    Text("Optional. Once set, this shows in place of the name everywhere.")
                }

                Section("Photo") {
                    photoPreview
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    if pendingPhotoData != nil || (currentPhoto != nil && !pendingPhotoRemoved) {
                        Button("Remove Photo", role: .destructive) {
                            pendingPhotoData = nil
                            selectedPhotoItem = nil
                            pendingPhotoRemoved = true
                        }
                    }
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            pendingPhotoData = data
                            pendingPhotoRemoved = false
                        }
                    }
                }

                Section {
                    if YouTubeURL.videoID(from: videoURLText) != nil {
                        YouTubeThumbnailButton(urlString: videoURLText, title: name)
                            .frame(height: 160)
                            .listRowInsets(EdgeInsets())
                    }
                    TextField("YouTube link", text: $videoURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Video")
                } footer: {
                    Text("Paste a YouTube link. Shown as a thumbnail here — tap to play. Auto-plays muted during workouts.")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
            }
            .themedListBackground()
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var photoPreview: some View {
        if let pendingPhotoData, let uiImage = UIImage(data: pendingPhotoData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
        } else if !pendingPhotoRemoved, let currentPhoto {
            Image(uiImage: currentPhoto)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
        }
    }

    private func save() {
        exercise.name = name.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVideoURL = videoURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.label = trimmedLabel.isEmpty ? nil : trimmedLabel
        exercise.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        exercise.videoURL = trimmedVideoURL.isEmpty ? nil : trimmedVideoURL

        if let pendingPhotoData {
            if let fileName = try? GeneratedExerciseImageStore.save(pendingPhotoData, exerciseID: exercise.id) {
                exercise.generatedImageFileName = fileName
            }
        } else if pendingPhotoRemoved {
            if let oldFileName = exercise.generatedImageFileName {
                GeneratedExerciseImageStore.delete(fileName: oldFileName)
            }
            exercise.generatedImageFileName = nil
        }

        exercise.markDirty()
        try? context.save()
        dismiss()
    }
}
