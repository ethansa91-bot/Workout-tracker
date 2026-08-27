import UIKit

/// On-disk storage for AI-generated exercise images, mirroring
/// `BundleThenDiskIconProvider`'s Application Support convention for runtime-generated
/// pictures. Filenames are keyed by the owning exercise's id, so regenerating an
/// exercise's image simply overwrites the same file rather than accumulating orphans.
enum GeneratedExerciseImageStore {
    private static let fileManager = FileManager.default

    /// Re-encodes `data` as JPEG and writes it to
    /// Application Support/GeneratedExerciseImages/<exerciseID>.jpg, returning the
    /// filename to store on the `Exercise` record.
    static func save(_ data: Data, exerciseID: UUID) throws -> String {
        guard let uiImage = UIImage(data: data), let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
            throw StoreError.invalidImageData
        }
        guard let directory else {
            throw StoreError.noStorageDirectory
        }
        let fileName = "\(exerciseID.uuidString).jpg"
        try jpegData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    static func load(fileName: String) -> UIImage? {
        guard let data = data(fileName: fileName) else { return nil }
        return UIImage(data: data)
    }

    /// The stored bytes as-is. Archiving uses this rather than `load` so the JPEG is
    /// copied verbatim instead of being decoded and re-encoded a second time.
    static func data(fileName: String) -> Data? {
        guard let url = directory?.appendingPathComponent(fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Writes bytes already known to be a valid image, keeping the archive's original
    /// filename. Distinct from `save`, which re-encodes and derives the name from the
    /// exercise id — on restore the name must survive, because `Exercise` rows in the
    /// same archive already point at it.
    static func restore(_ data: Data, fileName: String) throws {
        guard let directory else { throw StoreError.noStorageDirectory }
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    /// Every generated-image file currently on disk, by filename.
    static func allFileNames() -> [String] {
        guard let directory else { return [] }
        let contents = try? fileManager.contentsOfDirectory(atPath: directory.path)
        return contents ?? []
    }

    static func delete(fileName: String) {
        guard let url = directory?.appendingPathComponent(fileName) else { return }
        try? fileManager.removeItem(at: url)
    }

    private static var directory: URL? {
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = supportDir.appendingPathComponent("GeneratedExerciseImages", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum StoreError: Error {
        case invalidImageData
        case noStorageDirectory
    }
}
