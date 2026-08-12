import SwiftUI
import UIKit

/// App-wide visual language: warm cream grounds, white elevated cards, a deep green
/// accent, and a rust tone for secondary numeric data — extracted from the approved
/// style mockup and applied consistently everywhere instead of the system defaults.
extension Color {
    /// Page/List/Form ground.
    static let appBackground = Color(light: UIColor(red: 0.953, green: 0.933, blue: 0.894, alpha: 1),
                                      dark: UIColor(red: 0.094, green: 0.086, blue: 0.059, alpha: 1))
    /// A slightly deeper cream, for subtle banding behind a background gradient.
    static let appBackgroundDeep = Color(light: UIColor(red: 0.918, green: 0.890, blue: 0.827, alpha: 1),
                                          dark: UIColor(red: 0.055, green: 0.051, blue: 0.035, alpha: 1))
    /// Card/row surface, elevated above the background.
    static let appSurface = Color(light: .white,
                                   dark: UIColor(red: 0.141, green: 0.122, blue: 0.090, alpha: 1))
    /// Primary text.
    static let appInk = Color(light: UIColor(red: 0.110, green: 0.106, blue: 0.094, alpha: 1),
                               dark: UIColor(red: 0.945, green: 0.929, blue: 0.890, alpha: 1))
    /// Secondary/caption text.
    static let appInkMuted = Color(light: UIColor(red: 0.549, green: 0.525, blue: 0.455, alpha: 1),
                                    dark: UIColor(red: 0.655, green: 0.612, blue: 0.525, alpha: 1))
    /// Hairline separators between rows within a card.
    static let appHairline = Color(light: UIColor(red: 0.910, green: 0.882, blue: 0.816, alpha: 1),
                                    dark: UIColor(red: 0.235, green: 0.212, blue: 0.165, alpha: 1))
    /// Secondary numeric accent — durations, counts, historical figures.
    static let appRust = Color(light: UIColor(red: 0.714, green: 0.357, blue: 0.165, alpha: 1),
                                dark: UIColor(red: 0.816, green: 0.475, blue: 0.290, alpha: 1))
    /// Primary accent — same palette as `AccentColor` in the asset catalog, exposed as
    /// a token so it can be applied explicitly where the asset alone doesn't cascade
    /// (TabView tint doesn't reliably pick up AccentColor on every iOS version).
    static let appAccent = Color(light: UIColor(red: 0.169, green: 0.431, blue: 0.306, alpha: 1),
                                  dark: UIColor(red: 0.361, green: 0.663, blue: 0.529, alpha: 1))

    fileprivate init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension UIColor {
    /// Same palette as `Color.appAccent`, for UIKit appearance proxies.
    static let appAccent = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.361, green: 0.663, blue: 0.529, alpha: 1)
        : UIColor(red: 0.169, green: 0.431, blue: 0.306, alpha: 1)
    }
    static let appBackground = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.094, green: 0.086, blue: 0.059, alpha: 1)
        : UIColor(red: 0.953, green: 0.933, blue: 0.894, alpha: 1)
    }
    static let appSurface = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.141, green: 0.122, blue: 0.090, alpha: 1)
        : .white
    }
    static let appInk = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.945, green: 0.929, blue: 0.890, alpha: 1)
        : UIColor(red: 0.110, green: 0.106, blue: 0.094, alpha: 1)
    }
}

extension Font {
    /// The mockup's serif display type for titles and hero figures — SwiftUI's built-in
    /// serif design, no custom font files needed.
    static func appSerif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

/// White rounded card with a soft shadow instead of a hard border — the mockup's
/// signature surface treatment, standing in for the system's plain grouped-row look.
private struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 20) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    /// Applies the app's cream ground to a `List`/`Form`, replacing the system grouped
    /// background — the rows themselves stay white, reading as cards floating on cream.
    func themedListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.appBackground)
    }
}
