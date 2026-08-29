import UIKit

/// On-disk storage for AI-generated exercise images, mirroring
/// `BundleThenDiskIconProvider`'s Application Support convention for runtime-generated
/// pictures. Filenames are keyed by the owning exercise's id, so regenerating an
/// exercise's image simply overwrites the same file rather than accumulating orphans.
enum GeneratedExerciseImageStore {
    private static let fileManager = FileManager.default

    /// Decoded images, keyed by filename.
    ///
    /// `load` reads the file and decodes the JPEG afresh on every call, and it's called
    /// from inside SwiftUI bodies — during a Follow Along step that meant a disk read and
    /// a full decode on the main thread every time the view re-rendered. `NSCache` also
    /// means the images are given up automatically under memory pressure, which matters
    /// on a screen left open for hours.
    private static let cache = NSCache<NSString, UIImage>()

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
        // Regenerating an exercise's image overwrites the same filename, so the previous
        // decode has to go or the old picture would keep being served.
        cache.removeObject(forKey: fileName as NSString)
        return fileName
    }

    static func load(fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        guard let data = data(fileName: fileName), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// Whether a file is present, without reading or decoding it.
    ///
    /// Callers that only need to know whether an exercise has a picture used to go
    /// through `load`, paying for a full JPEG decode to answer a yes/no question.
    static func exists(fileName: String) -> Bool {
        guard let url = directory?.appendingPathComponent(fileName) else { return false }
        return fileManager.fileExists(atPath: url.path)
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
        cache.removeObject(forKey: fileName as NSString)
    }

    /// Every generated-image file currently on disk, by filename.
    static func allFileNames() -> [String] {
        guard let directory else { return [] }
        let contents = try? fileManager.contentsOfDirectory(atPath: directory.path)
        return contents ?? []
    }

    static func delete(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
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
