import SwiftUI

/// Horizontal strip of every step in the current time section. Tapping only *selects* a
/// step — it never jumps immediately, since jumping back is a real redo (discards
/// progress) and shouldn't happen from a stray tap.
struct SessionScrubStripView: View {
    let steps: [TimeSectionStep]
    let currentIndex: Int
    let completedIndices: Set<Int>
    let onSelect: (Int) -> Void

    /// Small-screen baseline (iPhone SE/mini logical width) chip sizing scales from.
    private static let referenceWidth: CGFloat = 375
    /// Minimum chip width — double the original fixed 64pt chip.
    private static let baseChipWidth: CGFloat = 128
    /// Chip width grows 1:1 with screen width beyond `referenceWidth`, capped here.
    private static let maxGrowth: CGFloat = 1.15
    /// Height is always 25% less than width, so the chip reads as a rectangle at every size.
    private static let heightRatio: CGFloat = 0.75

    private static var maxChipHeight: CGFloat { baseChipWidth * maxGrowth * heightRatio }

    private static func chipWidth(for availableWidth: CGFloat) -> CGFloat {
        let growth = min(max(availableWidth / referenceWidth, 1.0), maxGrowth)
        return baseChipWidth * growth
    }

    var body: some View {
        GeometryReader { geometry in
            let chipWidth = Self.chipWidth(for: geometry.size.width)
            let chipHeight = chipWidth * Self.heightRatio

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            stepChip(step, index: index, width: chipWidth, height: chipHeight)
                                .id(index)
                                .onTapGesture { onSelect(index) }
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: currentIndex) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
        .frame(height: Self.maxChipHeight)
    }

    private func stepChip(_ step: TimeSectionStep, index: Int, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(chipTitle(step))
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(step.durationSeconds)s")
                .font(.caption2)
                .foregroundStyle(index == currentIndex ? Color.white.opacity(0.85) : Color.secondary)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: height)
        .background(background(for: index))
        .foregroundStyle(index == currentIndex ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Border only for a step with an explicit color — not the plain default look —
        // always on (not just while the fill is the light preview tint), so the deep
        // color stays visible as a frame even once the fill turns into that same deep
        // color on the active chip. strokeBorder (not stroke) draws entirely inside the
        // shape's bounds instead of straddling the edge — stroke's half-outside overflow
        // was getting clipped at the chip's own top/bottom edge, cutting the corners.
        .overlay {
            if let stepColor = step.color?.color {
                RoundedRectangle(cornerRadius: 12).strokeBorder(stepColor, lineWidth: 2)
            }
        }
    }

    private func chipTitle(_ step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    /// Aesthetic test: the fill stays the same plain gray for every non-active chip
    /// regardless of color — lighter while upcoming, slightly darker once completed,
    /// same as Rest/Get Ready always looked — and a colored step is signaled only by
    /// its border (see `stepChip`), not by tinting the fill. Only the active chip's
    /// fill still shows the actual color (or the default accent if it has none).
    private func background(for index: Int) -> AnyShapeStyle {
        if index == currentIndex {
            return AnyShapeStyle(steps[index].color?.color ?? .accentColor)
        }
        if completedIndices.contains(index) { return AnyShapeStyle(Color.secondary.opacity(0.3)) }
        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }
}
