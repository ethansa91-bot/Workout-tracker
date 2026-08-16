import Foundation

/// A backend capable of producing an exercise movement image from a text description and
/// a fixed illustration style.
protocol ExerciseImageGenerating {
    /// Whether this provider is usable right now (e.g. a required API key is configured).
    var isAvailable: Bool { get }

    func generateImage(description: String, style: ExerciseImageStyle) async throws -> Data
}

enum ExerciseImageGenerationError: LocalizedError {
    case providerUnavailable
    case invalidResponse
    case emptyDescription
    /// The provider's own error message (e.g. Google's JSON error body), surfaced
    /// as-is so quota/billing/model issues are diagnosable from the UI instead of
    /// collapsing into a generic "unexpected response".
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable: "This image generator isn't configured."
        case .invalidResponse: "The image generator returned an unexpected response."
        case .emptyDescription: "Enter a short description of the movement first."
        case .serverMessage(let message): message
        }
    }
}
