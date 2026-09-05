import SwiftUI

/// Horizontal strip of every step in the current time section. Tapping only *selects* a
/// step — it never jumps immediately, since jumping back is a real redo (discards
/// progress) and shouldn't happen from a stray tap.
struct SessionScrubStripView: View {
    let steps: [TimeSectionStep]
    let currentIndex: Int
    let completedIndices: Set<Int>
    let onSelect: (Int) -> Void
    /// Height derived from the container's width by the caller, so the strip reserves
    /// exactly what its chips occupy rather than the widest-device maximum.
    var fixedHeight: CGFloat?

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

    /// The height the strip actually needs at a given width. The chips scale with the
    /// screen, so reserving the maximum unconditionally left 7–14pt of dead space
    /// inside the strip on anything narrower than the widest phone — space no amount
    /// of outer padding could reclaim, because it was inside this view's own frame.
    static func height(for availableWidth: CGFloat) -> CGFloat {
        chipWidth(for: availableWidth) * heightRatio
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
        // Falls back to the maximum only when a caller hasn't supplied a width.
        .frame(height: fixedHeight ?? Self.maxChipHeight)
    }

    private func stepChip(_ step: TimeSectionStep, index: Int, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(step.displayTitle)
                .font(.caption)
                .lineLimit(2)
                // Folding the execution type into the title made these longer than the
                // two lines a chip has room for, so they scale down rather than truncate
                // the type — which is the half that distinguishes adjacent chips.
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(height: height * 0.4)
            Text("\(step.durationSeconds)s")
                .font(.system(size: height * 0.32, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(index == currentIndex ? Color.white.opacity(0.85) : Color.secondary)
                .frame(maxHeight: .infinity)
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
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(step.resolvedColor.color, lineWidth: 2)
        }
    }



    /// Aesthetic test: the fill stays the same plain gray for every non-active chip
    /// regardless of color — lighter while upcoming, slightly darker once completed,
    /// same as Rest/Get Ready always looked — and a colored step is signaled only by
    /// its border (see `stepChip`), not by tinting the fill. Only the active chip's
    /// fill still shows the actual color (or the default accent if it has none).
    private func background(for index: Int) -> AnyShapeStyle {
        if index == currentIndex {
            return AnyShapeStyle(steps[index].resolvedColor.color)
        }
        if completedIndices.contains(index) { return AnyShapeStyle(Color.secondary.opacity(0.3)) }
        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }
}
