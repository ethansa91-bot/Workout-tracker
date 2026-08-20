import SwiftUI

/// A scrolling number wheel for manual weight entry — the Clock app's timer picker,
/// with a whole-number column and a decimal column.
///
/// Starts at 1 rather than 0: a loaded set weighing nothing is a bodyweight set, which
/// is its own weight source. The range runs high enough that no gym load hits the end.
struct WeightWheelPicker: View {
    @Binding var value: Double
    let unit: String

    /// The lowest weight the wheel offers. Below this is bodyweight, which is its own
    /// weight source rather than a load of zero.
    static let minimumValue: Double = 1

    /// 1...600 covers any plate stack or dumbbell in kg or lb.
    private static let wholeRange = Array(1...600)
    /// Tenths — enough for half-kilo plates and the 2.5 lb micro-loads.
    private static let fractionRange = Array(0...9)

    private var wholeBinding: Binding<Int> {
        Binding(
            get: { max(1, Int(value)) },
            set: { value = Double($0) + fractionalPart }
        )
    }

    private var fractionBinding: Binding<Int> {
        Binding(
            get: { Int((value * 10).rounded()) % 10 },
            set: { value = Double(max(1, Int(value))) + Double($0) / 10 }
        )
    }

    private var fractionalPart: Double {
        Double(Int((value * 10).rounded()) % 10) / 10
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Weight", selection: wholeBinding) {
                ForEach(Self.wholeRange, id: \.self) { number in
                    Text("\(number)").tag(number)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Text(".")
                .font(.title3.weight(.semibold))

            Picker("Decimal", selection: fractionBinding) {
                ForEach(Self.fractionRange, id: \.self) { digit in
                    Text("\(digit)").tag(digit)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
        .frame(height: 120)
    }
}
