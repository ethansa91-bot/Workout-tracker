import SwiftUI

protocol IconImageProvider {
    /// Resolves an item's icon. `identifier` is the item's stable `id.uuidString`;
    /// `symbolFallback` is the SF Symbol assigned at seed/creation time.
    func image(identifier: String, symbolFallback: String) -> Image
}
