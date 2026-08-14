import SwiftUI

/// Horizontal strip of every step in the current time section. Tapping only *selects* a
/// step — it never jumps immediately, since jumping back is a real redo (discards
/// progress) and shouldn't happen from a stray tap.
struct SessionScrubStripView: View {
    let steps: [TimeSectionStep]
    let currentIndex: Int
    let completedIndices: Set<Int>
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        stepChip(step, index: index)
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

    private func stepChip(_ step: TimeSectionStep, index: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: chipIcon(step))
                .font(.title3)
            Text(chipTitle(step))
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(width: 64, height: 64)
        .background(background(for: index))
        .foregroundStyle(index == currentIndex ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chipIcon(_ step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.iconSymbolName ?? "figure.strengthtraining.traditional"
        case .rest: return "pause.circle"
        case .getReady: return "hourglass"
        }
    }

    private func chipTitle(_ step: TimeSectionStep) -> String {
        switch step.stepType {
        case .exercise: return step.exercise?.displayName ?? "Exercise"
        case .rest: return "Rest"
        case .getReady: return "Get Ready"
        }
    }

    private func background(for index: Int) -> AnyShapeStyle {
        if index == currentIndex { return AnyShapeStyle(Color.accentColor) }
        if completedIndices.contains(index) { return AnyShapeStyle(Color.secondary.opacity(0.3)) }
        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }
}
