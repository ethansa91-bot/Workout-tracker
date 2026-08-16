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
        guard let url = directory?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
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
