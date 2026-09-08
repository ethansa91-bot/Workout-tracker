import SwiftUI

/// Horizontal strip of everything ahead in this consecutive run of Follow Along
/// sections — every remaining round of the current section, then any Follow Along
/// section that follows it, round/section boundaries marked with small text rather
/// than a chip. Tapping only *selects* a step — it never jumps immediately, since
/// jumping back is a real redo (discards progress) and shouldn't happen from a stray
/// tap; jumping ahead across a section/round boundary is a bigger move than a plain
/// in-pass skip and gets its own confirmation wording from the caller.
struct SessionScrubStripView: View {
    let items: [FollowAlongStripItem]
    let currentItemID: String?
    let completedItemIDs: Set<String>
    let onSelect: (FollowAlongStripItem) -> Void
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
                        ForEach(items) { item in
                            cell(item, width: chipWidth, height: chipHeight)
                                .id(item.id)
                                .onTapGesture { onSelect(item) }
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: currentItemID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
                .onAppear {
                    guard let currentItemID else { return }
                    proxy.scrollTo(currentItemID, anchor: .center)
                }
            }
        }
        // Falls back to the maximum only when a caller hasn't supplied a width.
        .frame(height: fixedHeight ?? Self.maxChipHeight)
    }

    @ViewBuilder
    private func cell(_ item: FollowAlongStripItem, width: CGFloat, height: CGFloat) -> some View {
        switch item {
        case .step(let step, _, _):
            stepChip(title: step.displayTitle, seconds: step.durationSeconds, color: step.resolvedColor.color, item: item, width: width, height: height)
        case .rest(_, _, let seconds):
            stepChip(title: "Rest", seconds: seconds, color: PaletteColor.gray.color, item: item, width: width, height: height)
        case .roundSeparator(let label, _, _):
            separatorLabel(label)
        case .endMarker(let label):
            separatorLabel(label)
        }
    }

    /// Small centered text, not a square chip — a round/section boundary or the
    /// strip's own final "End of Section"/"End of Workout" marker. Never tappable:
    /// `onTapGesture` is attached uniformly by the caller, but there's no step behind
    /// one of these for `onSelect` to act on in any meaningful way, so it's a no-op.
    private func separatorLabel(_ text: String) -> some View {
        // "Section: Abs · Round 2 of 3" reads as one crowded line at chip width — split
        // on the same " · " `sectionRoundTitle` joins with, so the section name and the
        // round count each get their own row.
        let lines = text.components(separatedBy: " · ")
        return VStack(spacing: 2) {
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxHeight: .infinity)
    }

    private func stepChip(title: String, seconds: Int, color: Color, item: FollowAlongStripItem, width: CGFloat, height: CGFloat) -> some View {
        let isCurrent = item.id == currentItemID
        let isCompleted = completedItemIDs.contains(item.id)
        return VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .lineLimit(2)
                // Folding the execution type into the title made these longer than the
                // two lines a chip has room for, so they scale down rather than truncate
                // the type — which is the half that distinguishes adjacent chips.
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(height: height * 0.4)
            Text("\(seconds)s")
                .font(.system(size: height * 0.32, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : Color.secondary)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: height)
        .background(background(isCurrent: isCurrent, isCompleted: isCompleted, color: color))
        .foregroundStyle(isCurrent ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Border only for a step with an explicit color — not the plain default look —
        // always on (not just while the fill is the light preview tint), so the deep
        // color stays visible as a frame even once the fill turns into that same deep
        // color on the active chip. strokeBorder (not stroke) draws entirely inside the
        // shape's bounds instead of straddling the edge — stroke's half-outside overflow
        // was getting clipped at the chip's own top/bottom edge, cutting the corners.
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color, lineWidth: 2)
        }
    }

    /// Aesthetic test: the fill stays the same plain gray for every non-active chip
    /// regardless of color — lighter while upcoming, slightly darker once completed,
    /// same as Rest/Get Ready always looked — and a colored step is signaled only by
    /// its border (see `stepChip`), not by tinting the fill. Only the active chip's
    /// fill still shows the actual color (or the default accent if it has none).
    private func background(isCurrent: Bool, isCompleted: Bool, color: Color) -> AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(color) }
        if isCompleted { return AnyShapeStyle(Color.secondary.opacity(0.3)) }
        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }
}
