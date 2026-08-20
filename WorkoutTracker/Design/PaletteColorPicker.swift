import SwiftUI

/// Reusable 8-swatch grid for picking a `PaletteColor` — tap to select, tap the
/// already-selected swatch again to clear it back to `nil`. Shared by the
/// follow-along step color picker and the equipment level color picker.
struct PaletteColorPicker: View {
    @Binding var selection: PaletteColor?
    var swatchSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            ForEach(PaletteColor.allCases) { option in
                Button {
                    selection = (selection == option) ? nil : option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay {
                            if selection == option {
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
