import SwiftUI

/// The single biggest lever for a cohesive, professional look without touching any
/// functionality: every SF Symbol in a row/header sits in a soft tinted chip instead
/// of floating bare. Used everywhere across Library, Workouts, Sessions, and History.
struct IconBadge: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
