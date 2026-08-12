import SwiftUI

/// Small tinted capsule label — "Custom", "Finished", "Locked", etc. Standardizes what
/// used to be a mix of plain caption text and ad hoc `Label`s into one consistent look.
struct StatusPill: View {
    let text: String
    var icon: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.15), in: Capsule())
    }
}
