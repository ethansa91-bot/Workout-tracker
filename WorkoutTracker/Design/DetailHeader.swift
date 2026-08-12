import SwiftUI

/// Shared header for detail screens (muscle/equipment/exercise/workout): a large icon
/// badge beside a title and optional subtitle. One consistent look instead of each
/// screen hand-rolling its own icon+text HStack.
struct DetailHeader: View {
    let systemName: String
    let title: String
    var subtitle: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: systemName, tint: tint, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.appSerif(.title3))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.appInkMuted)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
