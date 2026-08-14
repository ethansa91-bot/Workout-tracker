import SwiftUI
import SwiftData

/// Routes to the time/rep/EMOM/AMRAP section editor and owns the chrome shared by all
/// four: the title. Sections can no longer be deleted from inside their own editor —
/// only via swipe-to-delete on WorkoutEditorView's section list.
struct SectionEditorView: View {
    @Bindable var section: WorkoutSection
    /// True only when nothing precedes this on the stack yet (fresh by-time/by-rep
    /// workout creation) — Save should push a recap page. False (the default) means
    /// this was reached from an already-open recap page ("Manage Exercises"), so
    /// Save should just pop back to it instead of pushing a duplicate.
    var onSaveNavigatesToRecap: Bool = false

    var body: some View {
        Group {
            switch section.sectionType {
            case .time:
                TimeSectionEditorView(section: section, onSaveNavigatesToRecap: onSaveNavigatesToRecap)
            case .rep:
                RepSectionEditorView(section: section, onSaveNavigatesToRecap: onSaveNavigatesToRecap)
            case .emom, .amrap:
                QuickSectionEditorView(section: section, onSaveNavigatesToRecap: onSaveNavigatesToRecap)
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayName: String {
        if let name = section.name, !name.isEmpty { return name }
        // A By Time/By Reps workout's single section *is* the workout — its name is
        // more meaningful here than a generic section-type label. Personalized
        // workouts can have several sections, so they keep the section-type fallback.
        if let workout = section.workout, workout.kind != .personalized {
            return workout.name
        }
        return section.sectionType.fallbackSectionName
    }
}
