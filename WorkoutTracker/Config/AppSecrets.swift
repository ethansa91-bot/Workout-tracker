import Foundation

/// Reads Supabase config injected via Info.plist (sourced from the gitignored
/// `Secrets.xcconfig` — see `Secrets.xcconfig.example` at the repo root). Never
/// hardcode these values here.
enum AppSecrets {
    static var supabaseURL: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: raw)
        else {
            fatalError("Missing/invalid SupabaseURL in Info.plist — check Secrets.xcconfig is present and set as the project's base configuration.")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String, !key.isEmpty else {
            fatalError("Missing SupabaseAnonKey in Info.plist — check Secrets.xcconfig is present and set as the project's base configuration.")
        }
        return key
    }

    /// Optional — powers the Gemini option in the exercise image generator. Unlike the
    /// Supabase secrets above, absence isn't fatal: callers treat a nil key as "this
    /// provider isn't configured" and hide it rather than crash.
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
