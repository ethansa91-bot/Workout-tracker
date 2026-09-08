import SwiftUI
import SwiftData

/// Every workout `createNewVersion` has superseded in this lineage — reached from the
/// current version's own version-history icon as a sheet, never a tab, push, or list
/// of its own, since these are deliberately hidden from both the main Workouts list
/// and Archive.
///
/// A sheet rather than a push deliberately: picking a version below resets the owning
/// root list's `path` to just that version (the same mechanism Edit/Clone & Edit/Open
/// Latest Version use), and that reset only reliably reaches every screen it needs to
/// when nothing else is stacked on top of the root in the untyped way a push would be.
struct WorkoutVersionHistoryView: View {
    let workout: Workout
    /// The same closure `SessionRecapView` received from whichever root list ultimately
    /// opened the *current* version — passed straight through so picking a past version
    /// below resets that same root path instead of this sheet trying to navigate on
    /// its own.
    var onReplaceWithClone: ((Workout) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allWorkouts: [Workout]

    private var pastVersions: [Workout] {
        guard let groupID = workout.versionGroupID else { return [] }
        return allWorkouts
            .filter { $0.versionGroupID == groupID && $0.id != workout.id && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pastVersions.isEmpty {
                    ContentUnavailableView(
                        "No Past Versions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Versions this one replaced will show up here.")
                    )
                } else {
                    let versions = pastVersions
                    let lastID = versions.last?.id
                    List {
                        Section {
                            ForEach(versions) { version in
                                Button {
                                    onReplaceWithClone?(version)
                                    dismiss()
                                } label: {
                                    versionRow(version)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    // Not destructive — a plain clone, same as
                                    // `WorkoutListView`'s own swipe-to-clone, so an old
                                    // version can become a fresh, independent workout
                                    // with no lineage of its own.
                                    Button {
                                        copy(version)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                                .fullBleedRow(isLast: version.id == lastID)
                            }
                        } footer: {
                            Text("Locked exactly as they were when replaced. Tap one to open it, or swipe to copy it into a fresh, independent workout.")
                                .font(.footnote)
                                .foregroundStyle(Color.appInkMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }
                    .fullBleedList()
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func versionRow(_ version: Workout) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: version.displayType.iconSymbolName)
            VStack(alignment: .leading, spacing: 3) {
                Text(version.name)
                Text(version.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Always true here — only a used workout is ever superseded — but read
            // live rather than assumed, the same caution every other lock icon uses.
            if version.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func copy(_ version: Workout) {
        _ = WorkoutCloningService.clone(version, context: context)
    }
}
