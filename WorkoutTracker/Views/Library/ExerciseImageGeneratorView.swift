import SwiftUI

/// Sheet for generating an AI exercise image: describe the movement, pick one of the 3
/// fixed styles, generate, then hand the raw image data back to the caller. Presented
/// from `CustomExerciseFormView`, which is responsible for actually persisting the result
/// (nothing here touches disk or the `Exercise` model).
struct ExerciseImageGeneratorView: View {
    var initialDescription: String
    var initialStyle: ExerciseImageStyle
    var onUseImage: (Data, ExerciseImageStyle) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var selectedStyle: ExerciseImageStyle
    @State private var selectedProvider: Provider
    @State private var isGenerating = false
    @State private var generatedData: Data?
    @State private var errorMessage: String?

    private let geminiGenerator = GeminiImageGenerator()
    private let huggingFaceGenerator = HuggingFaceImageGenerator()

    private enum Provider: String, CaseIterable, Identifiable {
        case gemini = "Gemini"
        case huggingFace = "Hugging Face"
        var id: String { rawValue }
    }

    /// Providers with a configured key/token, in display order. Only providers in this
    /// list are ever selectable — an unconfigured one simply doesn't appear.
    private var availableProviders: [Provider] {
        Provider.allCases.filter { generator(for: $0).isAvailable }
    }

    private func generator(for provider: Provider) -> ExerciseImageGenerating {
        switch provider {
        case .gemini: geminiGenerator
        case .huggingFace: huggingFaceGenerator
        }
    }

    init(
        initialDescription: String,
        initialStyle: ExerciseImageStyle = .flatVector,
        onUseImage: @escaping (Data, ExerciseImageStyle) -> Void
    ) {
        self.initialDescription = initialDescription
        self.initialStyle = initialStyle
        self.onUseImage = onUseImage
        _description = State(initialValue: initialDescription)
        _selectedStyle = State(initialValue: initialStyle)
        let firstAvailable = Provider.allCases.first { provider in
            switch provider {
            case .gemini: AppSecrets.geminiAPIKey != nil
            case .huggingFace: AppSecrets.huggingFaceAPIToken != nil
            }
        }
        _selectedProvider = State(initialValue: firstAvailable ?? .huggingFace)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Movement Description") {
                    TextField("e.g. Standing dumbbell bicep curl", text: $description, axis: .vertical)
                }

                Section("Style") {
                    ForEach(ExerciseImageStyle.allCases) { style in
                        Button {
                            selectedStyle = style
                        } label: {
                            HStack {
                                Image(style.previewAssetName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(style.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedStyle == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                if availableProviders.count > 1 {
                    Section("Provider") {
                        Picker("Provider", selection: $selectedProvider) {
                            ForEach(availableProviders) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } else if availableProviders.isEmpty {
                    Section {
                        Text("No image generator configured — add GEMINI_API_KEY or HUGGINGFACE_API_TOKEN to Secrets.xcconfig.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let generatedData, let uiImage = UIImage(data: generatedData) {
                    Section {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button("Use This Image") {
                            onUseImage(generatedData, selectedStyle)
                            dismiss()
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(generatedData == nil ? "Generate" : "Try Again")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isGenerating || availableProviders.isEmpty || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .themedListBackground()
            .navigationTitle("Generate Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func generate() {
        errorMessage = nil
        isGenerating = true
        let description = description
        let style = selectedStyle
        let generator = generator(for: selectedProvider)

        Task {
            do {
                let data = try await generator.generateImage(description: description, style: style)
                await MainActor.run {
                    generatedData = data
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
