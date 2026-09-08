import SwiftUI

/// The Resources tab root: four big buttons onto the catalog screens that used to sit
/// behind Workouts' "Library" pane (Exercises/Equipment/Muscles) plus Templates, which
/// used to be a sibling pane of its own. One flat hub instead of a picker buried inside
/// another tab.
struct ResourcesView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageTitleBand(title: "Resources", reservesButtonRow: true)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        resourceButton(title: "Templates", icon: "square.stack.3d.up") {
                            SectionTemplatesView()
                        }
                        resourceButton(title: "Exercises", icon: "figure.strengthtraining.traditional") {
                            ExerciseListView()
                        }
                        resourceButton(title: "Equipment", icon: "dumbbell.fill") {
                            EquipmentListView()
                        }
                        resourceButton(title: "Muscles", icon: "figure.core.training") {
                            MuscleListView()
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Same card shape as `NewSectionTemplateSheet.typeButton`, inverted — white fill,
    /// green icon/label — and a fixed height so all four match exactly regardless of
    /// label length ("Templates" vs "Muscles").
    private func resourceButton<Destination: View>(
        title: String, icon: String, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .foregroundStyle(Color.appAccent)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
