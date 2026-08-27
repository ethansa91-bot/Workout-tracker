import SwiftUI
import SwiftData

struct LibraryHomeView: View {
    @Query private var muscles: [Muscle]
    @Query private var equipment: [Equipment]
    @Query private var exercises: [Exercise]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExerciseListView()
                } label: {
                    LibraryRow(title: "Exercises", count: exercises.count, systemImage: "figure.strengthtraining.traditional")
                }
                .fullBleedRow(isLast: false)
                NavigationLink {
                    EquipmentListView()
                } label: {
                    LibraryRow(title: "Equipment", count: equipment.count, systemImage: "dumbbell.fill")
                }
                .fullBleedRow(isLast: false)
                NavigationLink {
                    MuscleListView()
                } label: {
                    LibraryRow(title: "Muscles", count: muscles.count, systemImage: "figure.core.training")
                }
                .fullBleedRow()
            }
        }
        .fullBleedList()
    }
}

private struct LibraryRow: View {
    let title: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: systemImage)
            Text(title)
                .font(.body)
            Spacer()
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
