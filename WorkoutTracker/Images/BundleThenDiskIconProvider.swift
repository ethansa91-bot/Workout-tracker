import SwiftUI
import UIKit

/// Looks for a real per-item picture first — a bundled asset catalog entry named after
/// the item's identifier, then a file at Application Support/Icons/<identifier>.png —
/// and falls back to the seed/creation-assigned SF Symbol otherwise. This is the single
/// swap point: dropping a real picture in either location later replaces the
/// placeholder everywhere with no call-site changes.
struct BundleThenDiskIconProvider: IconImageProvider {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func image(identifier: String, symbolFallback: String) -> Image {
        if UIImage(named: identifier) != nil {
            return Image(identifier)
        }
        if let diskURL = onDiskIconURL(identifier: identifier),
           let data = try? Data(contentsOf: diskURL),
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: symbolFallback)
    }

    /// Where a runtime-generated icon for a post-install custom item would be written.
    /// Custom items can never ship in the compiled app bundle (it can't be rewritten
    /// after install), so this on-device sandbox location is their real "install
    /// package" equivalent.
    func onDiskIconDirectory() -> URL? {
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let iconsDir = supportDir.appendingPathComponent("Icons", isDirectory: true)
        try? fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        return iconsDir
    }

    private func onDiskIconURL(identifier: String) -> URL? {
        onDiskIconDirectory()?.appendingPathComponent("\(identifier).png")
    }
}
