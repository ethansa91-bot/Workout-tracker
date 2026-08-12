import Foundation
import CryptoKit

/// Seed catalog items must get the *same* id on every fresh install, or a reinstall
/// (new random UUIDs) collides with whatever was already pushed to Supabase under the
/// old ones — a unique-name conflict on tables like `muscle_categories`, or silent
/// duplicates on tables without a unique constraint. Deriving the id from a stable
/// namespace + name hash makes reseeding idempotent regardless of install history.
/// Custom/user-created items are unaffected — they keep using random `UUID()`, since
/// there's no pre-existing remote counterpart to reconcile with.
enum SeedIdentity {
    static func uuid(_ namespace: String, _ name: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace)|\(name)".utf8))
        let bytes = Array(digest.prefix(16))
        return bytes.withUnsafeBytes { $0.load(as: UUID.self) }
    }
}
