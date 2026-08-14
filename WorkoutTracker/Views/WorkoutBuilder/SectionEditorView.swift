import SwiftUI
import SwiftData

/// Routes to the time- or rep-block editor and owns the chrome shared by both: the
/// title. Blocks can no longer be deleted from inside their own editor — only via
/// swipe-to-delete on WorkoutEditorView's block list.
struct BlockEditorView: View {
    @Bindable var block: WorkoutBlock
    /// True only when nothing precedes this on the stack yet (fresh by-time/by-rep
    /// workout creation) — Save should push a recap page. False (the default) means
    /// this was reached from an already-open recap page ("Manage Exercises"), so
    /// Save should just pop back to it instead of pushing a duplicate.
    var onSaveNavigatesToRecap: Bool = false

    var body: some View {
        Group {
            if block.blockType == .time {
                TimeBlockEditorView(block: block, onSaveNavigatesToRecap: onSaveNavigatesToRecap)
            } else {
                RepBlockEditorView(block: block, onSaveNavigatesToRecap: onSaveNavigatesToRecap)
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayName: String {
        if let name = block.name, !name.isEmpty { return name }
        // A By Time/By Reps workout's single block *is* the workout — its name is
        // more meaningful here than a generic block-type label. Personalized
        // workouts can have several blocks, so they keep the block-type fallback.
        if let workout = block.workout, workout.kind != .personalized {
            return workout.name
        }
        return block.blockType == .time ? "Follow Along Block" : "Rep Block"
    }
}
