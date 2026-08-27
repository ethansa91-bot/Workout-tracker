import SwiftUI
import UniformTypeIdentifiers

/// `FileDocument` over an archive that already exists on disk.
///
/// Unlike `WorkoutExportDocument`, which holds its JSON in memory, this wraps a file
/// URL: an archive carrying generated images can run to megabytes, and there's no
/// reason to keep all of it on the heap while the save panel is open.
struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        // Reading happens through `ArchiveImportService`, which needs a real file path
        // to unzip; this initializer exists only to satisfy the protocol.
        throw ArchiveError.notAnArchive
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: fileURL)
    }
}
