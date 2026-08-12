import UIKit

/// Applies the parts of the app's visual language that are safe to set via global
/// UIKit appearance proxies.
///
/// Deliberately does NOT touch `UINavigationBar.appearance()` (background, title
/// fonts, or otherwise): live testing found that assigning a custom
/// `UINavigationBarAppearance` to `standardAppearance`/`scrollEdgeAppearance` makes
/// the navigation title disappear entirely once a screen's `List` actually has rows
/// in it — it rendered fine over an empty `ContentUnavailableView` but vanished the
/// moment real scrollable content was present, regardless of whether custom fonts
/// were included. The nav/tab bar cream background is applied instead via SwiftUI's
/// own `.toolbarBackground(_:for:)`, cascaded from `ContentView`'s root `TabView` —
/// safe because it works with SwiftUI's own large-title collapse logic instead of
/// fighting it at the UIKit layer.
enum AppearanceConfiguration {
    static func apply() {
        UITableView.appearance().backgroundColor = .appBackground
        UITableView.appearance().separatorColor = UIColor.appInk.withAlphaComponent(0.08)
        UICollectionView.appearance().backgroundColor = .appBackground
    }
}
