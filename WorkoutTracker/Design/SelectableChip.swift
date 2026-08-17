import SwiftUI

/// A tappable capsule chip for multi-select "filter-style" pickers — tinted fill when
/// selected, a faint tint wash + tinted border when not, so a group of chips reads as
/// a distinct color family even before anything's selected. Consolidates what used to
/// be near-identical private helpers in `ExerciseQuickFilterView`, `EquipmentListView`,
/// and `EquipmentDetailView`.
struct SelectableChip: View {
    var icon: String? = nil
    let title: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    /// Capped at 40 characters — a safety limit for whatever text gets passed in, not
    /// a normal case (catalog names are always well under this).
    private var truncatedTitle: String {
        title.count > 40 ? String(title.prefix(40)) + "…" : title
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: isSelected ? "\(icon).fill" : icon)
                }
                Text(truncatedTitle)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : tint)
            .background(isSelected ? tint : tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : tint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
