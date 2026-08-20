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
    /// Destructive actions — a muted brick red in the same tonal family as
    /// `appAccent` (comparably deep/desaturated, not a stark system red), so
    /// destructive buttons read as part of this palette instead of clashing with it.
    static let appDanger = Color(light: UIColor(red: 0.780, green: 0.325, blue: 0.298, alpha: 1),
                                  dark: UIColor(red: 0.867, green: 0.494, blue: 0.463, alpha: 1))
    /// Light neutral gray for expanded/highlighted list rows — a subtle, non-branded
    /// highlight, used instead of a heavier accent tint (e.g. an expanded accordion row).
    static let appHighlightGray = Color(light: UIColor(white: 0.91, alpha: 1),
                                         dark: UIColor(white: 0.24, alpha: 1))

    // MARK: - Follow-along step colors
    //
    // The per-exercise color picker (`PaletteColor`) needs a few hues this palette
    // doesn't otherwise have (blue, brown, yellow, purple) — matched to the same
    // deep/muted tone as `appAccent`/`appRust`/`appDanger` above rather than bright
    // system colors, so a colored step reads as part of this app's palette instead of
    // clashing with it. Green/orange/red/gray reuse `appAccent`/`appRust`/`appDanger`/
    // `appInkMuted` directly instead of duplicating them.
    static let appStepBlue = Color(light: UIColor(red: 0.204, green: 0.376, blue: 0.529, alpha: 1),
                                    dark: UIColor(red: 0.353, green: 0.596, blue: 0.706, alpha: 1))
    static let appStepBrown = Color(light: UIColor(red: 0.451, green: 0.325, blue: 0.220, alpha: 1),
                                     dark: UIColor(red: 0.678, green: 0.522, blue: 0.384, alpha: 1))
    static let appStepYellow = Color(light: UIColor(red: 0.710, green: 0.573, blue: 0.204, alpha: 1),
                                      dark: UIColor(red: 0.827, green: 0.706, blue: 0.404, alpha: 1))
    static let appStepPurple = Color(light: UIColor(red: 0.427, green: 0.294, blue: 0.478, alpha: 1),
                                      dark: UIColor(red: 0.612, green: 0.455, blue: 0.663, alpha: 1))

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
