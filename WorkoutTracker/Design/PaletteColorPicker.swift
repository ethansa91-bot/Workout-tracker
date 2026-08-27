import SwiftUI

/// Reusable 8-swatch grid for picking a `PaletteColor`. Tapping selects; there is no
/// way to clear back to `nil`, because a nil selection is displayed as a real default
/// rather than as "nothing chosen". Shared by the follow-along step color picker and
/// the equipment level color picker.
struct PaletteColorPicker: View {
    @Binding var selection: PaletteColor?
    var swatchSize: CGFloat = 28
    /// Which swatch reads as ticked while `selection` is still nil — the color the
    /// caller displays for an unset value. `nil` leaves nothing ticked, which is what
    /// the equipment picker wants.
    var defaultSelection: PaletteColor?

    private var tickedOption: PaletteColor? { selection ?? defaultSelection }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(PaletteColor.allCases) { option in
                Button {
                    // No clearing: every step always has a color selected, so tapping
                    // the current swatch is a no-op rather than a way back to "unset".
                    selection = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay {
                            if tickedOption == option {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
