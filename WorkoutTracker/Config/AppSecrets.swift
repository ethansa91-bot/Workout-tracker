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
}
