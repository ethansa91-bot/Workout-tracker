import SwiftUI

/// "Marc followed you — you're following back", with an undo.
///
/// A banner rather than an alert: this appears unprompted on foreground, and an alert
/// would interrupt whatever the user actually opened the app to do. It auto-dismisses,
/// so ignoring it is a valid response.
struct MutualFollowBanner: View {
    let users: [FollowedUser]
    let onUndo: () -> Void
    let onDismiss: () -> Void

    /// Long enough to read two lines and reach for Undo, short enough not to sit over
    /// the UI while the user is trying to use it.
    private static let visibleSeconds: Double = 6

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: "person.2.fill", tint: Color.appAccent, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.appSerif(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.appInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // Undo only when there's exactly one — undoing an ambiguous "and 2 others"
            // would be a destructive action with no way to see what it affected. With
            // several, the Following list is the honest place to make that choice.
            if users.count == 1 {
                Button("Undo", action: onUndo)
                    .font(.appSerif(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appDanger)
                    .buttonStyle(.plain)
            } else {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appInkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .cardStyle()
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: users.map(\.id)) {
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private var headline: String {
        guard let first = users.first else { return "" }
        if users.count == 1 {
            return "\(first.resolvedDisplayName) followed you"
        }
        return "\(first.resolvedDisplayName) and \(users.count - 1) other\(users.count == 2 ? "" : "s") followed you"
    }

    private var detail: String {
        users.count == 1
            ? "You're following them back, so you'll see the workouts they publish."
            : "You're following them back. Manage this in Settings under Sharing."
    }
}
