import Foundation

/// Reads API keys injected via Info.plist (sourced from the gitignored
/// `Secrets.xcconfig` — see `Secrets.xcconfig.example` at the repo root). Never
/// hardcode these values here.
enum AppSecrets {
    /// Optional — powers the Gemini option in the exercise image generator. Absence
    /// isn't fatal: callers treat a nil key as "this provider isn't configured" and
    /// hide it rather than crash.
    static var geminiAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String, !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Optional — powers the Hugging Face option in the exercise image generator. Same
    /// non-fatal-absence contract as `geminiAPIKey`.
    static var huggingFaceAPIToken: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "HuggingFaceAPIToken") as? String, !key.isEmpty else {
            return nil
        }
        return key
    }
}
