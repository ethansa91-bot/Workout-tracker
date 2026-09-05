import SwiftUI

/// Tags on a list row — the on-white counterpart to `HeaderTagPills`, which paints for the
/// green band.
///
/// Deliberately not `SelectableChip`: nothing here is selectable, and a chip's tap target
/// inside a `NavigationLink` row would compete with the row itself.
struct RowTagPills: View {
    let tags: [WorkoutTag]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 4, rowSpacing: 4) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(Color.appStepBlue)
                        .background(Color.appStepBlue.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}
