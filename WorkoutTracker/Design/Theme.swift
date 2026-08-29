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
    /// Deep gray for the schedule's full-bleed day headers — dark enough to carry white
    /// text in either theme, and neutral so the dated bands don't compete with the
    /// accent-green title above them.
    static let appHeaderGray = Color(light: UIColor(white: 0.28, alpha: 1),
                                      dark: UIColor(white: 0.22, alpha: 1))

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

    /// Point-size variant, for type sized off its container rather than off a text
    /// style — a runner header whose name scales with the band it sits in.
    static func appSerif(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
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

extension View {
    /// A full-width row band, flush to both screen edges. Deliberately not `cardStyle()`:
    /// its rounded shadow needs a gutter to fall into, which is exactly what makes rows
    /// float inset from a full-bleed header.
    ///
    /// Requires `.listStyle(.plain)` on the enclosing list — an inset-grouped section
    /// keeps its own side margins whatever the row insets say.
    ///
    /// `isLast` closes off a group: the separator is drawn between adjacent rows only, so
    /// a single-row group gets none at all.
    func fullBleedRow(isLast: Bool = true) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            // A trailing inset, not zero on all four sides: a `NavigationLink` in a list
            // puts its disclosure chevron against the row's trailing edge, and zeroing
            // that edge parked the chevron hard against the screen. The 16pt here is what
            // pulls it in level with the content. `listRowBackground` still paints the
            // band edge to edge, so the row itself stays full-bleed.
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
            .listRowBackground(Color.appSurface)
            .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
            .listRowSeparatorTint(Color.appHairline)
            // Both ends sit 16pt from the screen, so the line is symmetric and its right
            // end lands exactly under the chevron. The trailing guide is the row's own
            // edge, not `width - 16`: the row is already inset 16pt on that side by
            // `listRowInsets`, so subtracting again would stop the line 32pt in — short
            // of the chevron it's meant to line up with.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
            .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
    }

    /// The standard configuration for a list using `fullBleedRow` — plain style is what
    /// lets rows and headers reach the screen edges, and the zero min row height keeps a
    /// zero-inset row from being padded back out to 44pt.
    func fullBleedList() -> some View {
        self
            .listStyle(.plain)
            .listSectionSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .themedListBackground()
    }
}

/// A tab root's title, drawn in-content rather than as a navigation title.
///
/// Deliberately not a `UINavigationBar` appearance override: `AppearanceConfiguration`
/// documents a concrete bug where that made nav titles vanish once a list had real rows.
/// A view using this should set `.navigationTitle("")` so the two don't stack.
/// An `accessory` is drawn below the title inside the same band — a tab's own control
/// (Overview's pane picker) reading as part of the header rather than floating under it.
/// The height a navigation-bar button occupies, reserved at the top of every band.
///
/// Buttons live in the bar above, which iOS sizes to its contents — so a screen with no
/// button had a shorter bar and everything below it shifted up. Reserving the strip in
/// the band instead means content starts at the same place whether a button is there or
/// not, with no dependency on what the bar contains.
enum HeaderMetrics {
    /// Breathing room above the band's title — deliberately small, because the
    /// navigation bar above already holds the toolbar buttons.
    static let bandTopInset: CGFloat = 4
    /// Stands in for the button row on a screen that has no toolbar button.
    ///
    /// On iPhone the navigation bar shrinks when a screen has no toolbar item, so those
    /// pages rendered a visibly shorter header; reserving the row inside the band evens
    /// them up. Matched to the *rendered* bar rather than the 44pt button alone, since
    /// iOS pads above and below the glass capsule.
    ///
    /// Deliberately a plain `Color.clear` strip rather than an empty `ToolbarItem`: iOS
    /// draws a glass platter behind whatever a bar item holds, so an invisible one still
    /// renders as a ghost button.
    ///
    /// Zero on iPad, whose bar keeps its height with or without an item — reserving there
    /// added the gap it exists to prevent.
    static var buttonRowHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 53 : 0
    }
    static let bandBottomInset: CGFloat = 12
    static let bandHorizontalInset: CGFloat = 20
    /// Gutter for a row of `SelectableChip`s.
    ///
    /// Less than the 16pt a text row uses, because a chip draws 10pt of padding inside
    /// its own capsule — matching the outer value would push the chip's text 10pt right
    /// of the section title above it. 6 + 10 lands the text on the same 16pt line.
    static let chipGutter: CGFloat = 6
}

extension View {
    /// The shared geometry of every green header band.
    func headerBandStyle(reservesButtonRow: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // A frame that collapses to zero rather than an `if`: inserting and removing
            // a view is a structural change SwiftUI animates, which made the header
            // concertina when Overview's picker moved between a pane with a toolbar
            // button and one without. A height is just a layout value.
            Color.clear
                .frame(height: reservesButtonRow ? HeaderMetrics.buttonRowHeight : 0)
            self
        }
            .padding(.top, HeaderMetrics.bandTopInset)
            .padding(.bottom, HeaderMetrics.bandBottomInset)
            .padding(.horizontal, HeaderMetrics.bandHorizontalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appAccent)
    }
}

struct PageTitleBand<Accessory: View>: View {
    let title: String
    /// True on a screen with no toolbar button, so the band holds that row open itself
    /// and every tab's header stays the same height.
    var reservesButtonRow: Bool = false
    @ViewBuilder var accessory: Accessory

    private var hasAccessory: Bool { Accessory.self != EmptyView.self }

    var body: some View {
        VStack(alignment: .leading, spacing: hasAccessory ? 12 : 0) {
            HStack {
                Text(title)
                    .font(.appSerif(.title2))
                    .foregroundStyle(.white)
                Spacer()
            }
            accessory
        }
        .headerBandStyle(reservesButtonRow: reservesButtonRow)
    }
}

extension PageTitleBand where Accessory == EmptyView {
    init(title: String, reservesButtonRow: Bool = false) {
        self.init(title: title, reservesButtonRow: reservesButtonRow, accessory: { EmptyView() })
    }
}

/// A pushed screen's green header — the same band the tab roots get, sized to match,
/// for screens that keep their back button. Pair with `.navigationTitle("")` and
/// `.navigationBarTitleDisplayMode(.inline)` so the title doesn't render twice.
/// A full-bleed gray band titling a section of a `.plain` list — the Schedule's day
/// bands and the History detail's per-section bands, so the two read as the same kind
/// of divider.
///
/// Reaches both screen edges, which only works under `.listStyle(.plain)`: an
/// inset-grouped section keeps its own side margins whatever the row insets say.
struct ListBandHeader: View {
    let title: String
    /// A second, lighter line — what kind of section it is, how long it ran. Omitted
    /// where the title says everything (the Schedule's day bands).
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.appHeaderGray)
        .listRowInsets(EdgeInsets())
        // Stock headers uppercase their text, which mangles a date.
        .textCase(nil)
    }
}

/// A muted section label on the cream ground, standing in for a grouped list's header
/// now that `.plain` renders headers unstyled and flush-left.
struct FormSectionHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.appInkMuted)
            // Stock headers uppercase their text.
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
            .listRowInsets(EdgeInsets())
            // Sits on the cream ground rather than on a white band, the way a grouped
            // header did.
            .listRowBackground(Color.clear)
    }
}

/// The footnote under a section — an aside on the cream ground, not a row. Pairs with
/// `FormSectionHeader`, and exists for the same reason: `.plain` renders a stock footer as
/// an opaque band, which reads as another list row rather than as commentary.
struct FormSectionFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.appInkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

extension View {
    /// The horizontal gutter a form control needs once row insets are zeroed — without
    /// it a Stepper's ± or a segmented control sits flush against the screen edge.
    func formRowPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    /// A form control as a full-bleed row: its own gutter, then the shared band.
    func formRow(isLast: Bool = true) -> some View {
        formRowPadding()
            .fullBleedRow(isLast: isLast)
    }
}

/// A pushed screen's green header.
///
/// Carries the screen's identity so the content below it never has to repeat the name:
/// an optional one-line `subtitle` that expands on tap, and an optional trailing control
/// (typically the pencil that opens the screen's edit sheet).
struct PushedTitleBand<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    @State private var subtitleExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.appSerif(.title2))
                    .foregroundStyle(.white)
                trailing
                Spacer()
            }

            // One line until tapped: a description is usually a paragraph, and a header
            // that grows to fit one pushes the whole page down.
            if let subtitle, !subtitle.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { subtitleExpanded.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(subtitleExpanded ? nil : 1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .rotationEffect(.degrees(subtitleExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        // Same inset as the tab bands — here it clears the back button too.
        .headerBandStyle()
    }
}

extension PushedTitleBand where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// The in-content search field the green-band screens use instead of `.searchable`,
/// which renders in the navigation bar — with the title emptied for the band, that
/// leaves the field stranded in a bare bar above it.
///
/// A full-width white strip rather than a floating pill, so it reads as part of the page
/// the way the rows below it do.
struct InlineSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appInkMuted)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appInkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface)
    }
}

/// A band carrying only a control — no title row at all, so the accessory sits close
/// under the toolbar. An empty title string wouldn't do: `Text("")` still reserves a
/// line's height.
struct PageAccessoryBand<Accessory: View>: View {
    var reservesButtonRow: Bool = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        accessory
            .headerBandStyle(reservesButtonRow: reservesButtonRow)
    }
}
