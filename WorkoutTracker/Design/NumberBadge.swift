import SwiftUI

/// `IconBadge`'s twin for a position number — same square, same tint treatment, so a
/// numbered row sits in the layout exactly where an icon badge did and a colored
/// follow-along step keeps showing its color.
struct NumberBadge: View {
    let number: Int
    var tint: Color = .accentColor
    var size: CGFloat = 28

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
