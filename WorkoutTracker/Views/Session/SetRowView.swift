import SwiftUI

/// One set: pending (editable draft, +/- steps through the equipment's weight combos
/// and reps one at a time) or logged (read-only with a Cancel action).
struct SetRowView: View {
    let setNumber: Int
    let weightOptions: [Double]
    let weightUnit: String
    @Binding var reps: Int
    @Binding var weight: Double
    let isLogged: Bool
    let isWorseThanLast: Bool
    let onLog: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isWorseThanLast {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            Text("Set \(setNumber)")
                .font(.subheadline.weight(.medium))
                .frame(width: 46, alignment: .leading)

            weightStepper
            Text("×").foregroundStyle(.secondary)
            repsStepper

            Spacer()

            if isLogged {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button("Log", action: onLog)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .opacity(isLogged ? 0.7 : 1)
    }

    private var weightStepper: some View {
        HStack(spacing: 4) {
            Button {
                stepWeight(delta: -1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(isLogged)
            Text(formattedWeight(weight))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 60)
            Button {
                stepWeight(delta: 1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(isLogged)
        }
    }

    private var repsStepper: some View {
        HStack(spacing: 4) {
            Button {
                if reps > 0 { reps -= 1 }
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(isLogged)
            Text("\(reps)")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 22)
            Button {
                reps += 1
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(isLogged)
        }
    }

    private func stepWeight(delta: Int) {
        guard !weightOptions.isEmpty else {
            weight = max(0, weight + Double(delta) * 5)
            return
        }
        guard let currentIndex = weightOptions.firstIndex(where: { $0 == weight }) else {
            weight = weightOptions[delta > 0 ? 0 : weightOptions.count - 1]
            return
        }
        let newIndex = min(max(currentIndex + delta, 0), weightOptions.count - 1)
        weight = weightOptions[newIndex]
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value)) \(weightUnit)" : "\(value) \(weightUnit)"
    }
}
