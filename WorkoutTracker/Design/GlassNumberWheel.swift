import SwiftUI

/// A rolling number wheel in a glass popover — the fast way to reach a value that the ±
/// buttons would take dozens of taps to walk to, like a 120-second hold from zero.
///
/// The counterpart to `WeightWheelPicker`, which can't serve here: that one is
/// weight-shaped (a whole column plus a tenths column, floored at 1) and presents in a
/// sheet. This is the plain-integer version in the popover treatment `SectionCardView`
/// established.
///
/// No Save button, unlike `SectionCardView.positionWheel` — that one defers because
/// committing mid-scroll would reorder the list underneath it. A number in a form has
/// nothing to churn, so the wheel writes straight through and tapping outside closes it.
struct GlassNumberWheel: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// How each row reads — "8 reps", "60s". Defaults to the bare number.
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.appInk)
            Picker("", selection: $value) {
                ForEach(Array(range), id: \.self) { number in
                    Text(format(number)).tag(number)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
        .padding(.vertical, 12)
        .frame(width: 220, height: 240)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(.ultraThinMaterial)
    }
}
