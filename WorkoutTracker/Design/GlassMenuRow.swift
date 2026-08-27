import SwiftUI

/// A labelled value with a glass control on its trailing edge — the treatment the session
/// runner's equipment line uses, lifted out so a form can offer the same control.
///
/// Deliberately not a `Picker`: the runner established this shape for "what is this set
/// loaded with", and the record page asks the same question, so the two should look and
/// behave alike rather than diverging into a wheel or a segmented control.
struct GlassMenuRow<MenuContent: View>: View {
    let systemImage: String
    let title: String
    let value: String
    /// Greyed and inert — used where a choice exists but isn't available yet, such as the
    /// equipment line before an exercise has been picked.
    var isEnabled: Bool = true
    @ViewBuilder var menu: () -> MenuContent

    var body: some View {
        GlassRowChrome(systemImage: systemImage, title: title, value: value) {
            Menu {
                menu()
            } label: {
                GlassRowPencil(isEnabled: isEnabled)
            }
            .buttonStyle(.glass)
            .disabled(!isEnabled)
        }
    }
}

/// The same row where the choice is too large for a menu and opens a picker instead —
/// the exercise line, which has the whole catalog behind it.
struct GlassButtonRow: View {
    let systemImage: String
    let title: String
    let value: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        GlassRowChrome(systemImage: systemImage, title: title, value: value) {
            Button(action: action) {
                GlassRowPencil(isEnabled: isEnabled)
            }
            .buttonStyle(.glass)
            .disabled(!isEnabled)
        }
    }
}

/// Shared so the menu and button forms can't drift apart visually.
private struct GlassRowChrome<Control: View>: View {
    let systemImage: String
    let title: String
    let value: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            Text(title)
                .foregroundStyle(Color.appInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GlassEffectContainer {
                control()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlassRowPencil: View {
    let isEnabled: Bool

    var body: some View {
        Image(systemName: "pencil")
            .foregroundStyle(isEnabled ? Color.appAccent : Color.secondary)
    }
}
