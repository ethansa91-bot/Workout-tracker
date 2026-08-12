import SwiftUI
import SwiftData

/// Routes to the time- or rep-block editor and owns the chrome shared by both: the
/// title. Blocks can no longer be deleted from inside their own editor — only via
/// swipe-to-delete on WorkoutEditorView's block list.
struct BlockEditorView: View {
    @Bindable var block: WorkoutBlock

    var body: some View {
        Group {
            if block.blockType == .time {
                TimeBlockEditorView(block: block)
            } else {
                RepBlockEditorView(block: block)
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayName: String {
        if let name = block.name, !name.isEmpty { return name }
        return block.blockType == .time ? "Time Block" : "Rep Block"
    }
}
