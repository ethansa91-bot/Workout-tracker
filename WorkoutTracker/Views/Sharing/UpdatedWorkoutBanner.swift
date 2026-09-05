import SwiftUI

/// "Leg Day was updated", with a way to open the merge review. Sibling of
/// `MutualFollowBanner` — same unprompted-on-foreground reasoning applies here too, so it
/// gets the same treatment: a dismissible, auto-expiring banner rather than an alert.
struct UpdatedWorkoutBanner: View {
    let workouts: [Workout]
    let onReview: () -> Void
    let onDismiss: () -> Void

    private static let visibleSeconds: Double = 8

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: "arrow.triangle.2.circlepath", tint: Color.appAccent, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.appSerif(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                Text("The person you saved it from has published changes.")
                    .font(.caption)
                    .foregroundStyle(Color.appInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Review", action: onReview)
                .font(.appSerif(.subheadline, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .buttonStyle(.plain)
        }
        .padding(14)
        .cardStyle()
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: workouts.map(\.id)) {
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private var headline: String {
        guard let first = workouts.first else { return "" }
        if workouts.count == 1 {
            return "\(first.name) was updated"
        }
        return "\(first.name) and \(workouts.count - 1) other\(workouts.count == 2 ? "" : "s") were updated"
    }
}
