import Foundation

/// Image generator using Google's Gemini image-generation model. Requires
/// `AppSecrets.geminiAPIKey` to be configured (optional — see
/// `Secrets.xcconfig.example`); `isAvailable` reports false otherwise so callers can
/// simply hide this option rather than crash or force setup.
///
/// Note: Gemini image output models have historically shipped with a 0-request free
/// tier — generation only works once billing is enabled on the associated Google Cloud
/// project, even though text-only Gemini calls are free. A 429 RESOURCE_EXHAUSTED error
/// mentioning a "free_tier" quota of 0 means that, not a bug here.
///
/// Verify the model name/endpoint against Google's current docs when wiring this up —
/// the Gemini image-generation API surface has moved (model ids, response shape) since
/// this was written.
struct GeminiImageGenerator: ExerciseImageGenerating {
    private let model = "gemini-2.5-flash-image"

    var isAvailable: Bool { AppSecrets.geminiAPIKey != nil }

    func generateImage(description: String, style: ExerciseImageStyle) async throws -> Data {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExerciseImageGenerationError.emptyDescription }
        guard let apiKey = AppSecrets.geminiAPIKey else { throw ExerciseImageGenerationError.providerUnavailable }

        let prompt = "\(trimmed). \(style.promptModifier)"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw ExerciseImageGenerationError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            contents: [Content(parts: [Part(text: prompt)])],
            generationConfig: GenerationConfig(responseModalities: ["TEXT", "IMAGE"])
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data) {
                throw ExerciseImageGenerationError.serverMessage(errorBody.error.message)
            }
            throw ExerciseImageGenerationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard
            let base64 = decoded.candidates?.first?.content.parts.first(where: { $0.inlineData != nil })?.inlineData?.data,
            let imageData = Data(base64Encoded: base64)
        else {
            throw ExerciseImageGenerationError.invalidResponse
        }
        return imageData
    }

    // MARK: - Request

    private struct RequestBody: Encodable {
        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    private struct Content: Codable {
        let parts: [Part]
    }

    private struct Part: Codable {
        var text: String? = nil
        var inlineData: InlineData? = nil
    }

    private struct InlineData: Codable {
        let mimeType: String?
        let data: String
    }

    private struct GenerationConfig: Encodable {
        let responseModalities: [String]
    }

    // MARK: - Response

    private struct ResponseBody: Decodable {
        let candidates: [Candidate]?
    }

    private struct Candidate: Decodable {
        let content: Content
    }

    private struct GoogleErrorEnvelope: Decodable {
        let error: GoogleError
    }

    private struct GoogleError: Decodable {
        let message: String
    }
}
