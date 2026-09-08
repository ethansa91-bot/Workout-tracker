import Foundation
import SwiftData

enum WorkoutDisplayType: String {
    case empty, time, rep, emom, amrap, mixed

    /// User-facing label — "time" reads as "Follow Along" everywhere in the UI,
    /// matching the `byTime` workout kind's renamed label; EMOM/AMRAP are initialisms,
    /// not words, so they skip `.capitalized`.
    var label: String {
        switch self {
        case .time: return "Follow Along"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .empty, .rep, .mixed: return rawValue.capitalized
        }
    }

    var iconSymbolName: String {
        switch self {
        case .time: return "timer"
        case .rep: return "list.number"
        case .emom: return "repeat"
        case .amrap: return "flame"
        case .mixed: return "square.stack.3d.up.fill"
        case .empty: return "list.bullet.rectangle"
        }
    }
}

@Model
final class Workout: SyncableModel {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String?
    var createdAt: Date = Date.now
    var clonedFromWorkoutId: UUID?
    /// Dead column. Workouts no longer have a type — a workout is just its sections,
    /// and the only meaningful distinction is each section's own type. Kept (rather
    /// than dropped) because the store syncs through CloudKit, where removing a field
    /// is a schema change; nothing reads or writes it. `displayType` below is what
    /// labels and icons derive from now.
    var kindRaw: String = "personalized"
    var isArchived: Bool = false
    /// Whether this workout is currently published — flipped by `PublishWorkoutSheet`
    /// alongside its CloudKit call, so anything else can check synchronously rather
    /// than querying the server. What `markDirty()` below reads to decide whether an
    /// edit needs to go back out to followers.
    var isPublished: Bool = false
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    /// The publisher's `SharedWorkoutSummary.updatedAt` as of the last time this
    /// specific copy was downloaded or merged, for a workout saved from someone this
    /// user follows. Compared against the live value on every foreground sweep —
    /// `FollowService.syncWorkoutUpdates` — to notice when the source has moved on
    /// since. nil for a workout that was never downloaded, which is every workout
    /// before this existed and everything the user builds themselves.
    var sourceUpdatedAt: Date?
    /// Who published the workout this was downloaded from — `clonedFromWorkoutId`
    /// names *which* workout, this names *whose*, which is what the update sweep needs
    /// to know who to ask. Set once at download/merge time; nil for anything not
    /// downloaded, same as `sourceUpdatedAt`.
    var sourceOwnerRecordName: String?
    /// Shared by every workout in one version lineage — minted the first time
    /// `WorkoutCloningService.createNewVersion` is used on a locked workout, carried
    /// forward by each new version after that. nil means this workout has never been
    /// through a version edit. Deliberately separate from `clonedFromWorkoutId`, which
    /// already means "downloaded from a shared workout" for the follow/publish feature.
    var versionGroupID: UUID?
    /// True for a version `createNewVersion` has since superseded — hidden from both
    /// the main Workouts list and Archive, visible only from the current version's own
    /// version history. Distinct from `isArchived`: this isn't something the user put
    /// away, it's history that stays reachable but shouldn't clutter either list.
    var isSupersededVersion: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSection.workout)
    var sectionsStorage: [WorkoutSection]?
    var sections: [WorkoutSection] {
        get { sectionsStorage ?? [] }
        set { sectionsStorage = newValue }
    }

    /// Nullify, not deny: CloudKit doesn't support `.deny` delete rules at all. A
    /// deleted workout therefore leaves any session's `workout` nil (already an
    /// Optional, handled via optional chaining everywhere it's read) rather than
    /// blocking the delete. The user-facing delete paths in `WorkoutListView` and
    /// `ArchivedWorkoutsView` guard on `isLocked` so this only happens for workouts no
    /// live session references; `TestDataService`'s dev/QA cleanup deletes outright.
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.workout)
    var sessionsStorage: [WorkoutSession]?
    var sessions: [WorkoutSession] {
        get { sessionsStorage ?? [] }
        set { sessionsStorage = newValue }
    }

    // Exist only to satisfy CloudKit's "every relationship needs an inverse" rule for
    // the one-directional `RecurringWorkoutSchedule.workout`/`ScheduledWorkout.workout`
    // lookups — nothing in the app reads or writes these back-references.
    /// Organisational labels. Editable even while `isLocked`, since they carry no
    /// execution meaning — see `WorkoutEditingService.addTag`.
    @Relationship(inverse: \WorkoutTag.workoutsStorage)
    var tagsStorage: [WorkoutTag]?
    var tags: [WorkoutTag] {
        get { tagsStorage ?? [] }
        set { tagsStorage = newValue }
    }

    /// Live tags in a stable display order.
    var sortedTags: [WorkoutTag] {
        tags.filter { $0.deletedAt == nil }.sorted { $0.name < $1.name }
    }

    @Relationship(inverse: \RecurringWorkoutSchedule.workout)
    var recurringSchedules: [RecurringWorkoutSchedule]?
    @Relationship(inverse: \ScheduledWorkout.workout)
    var scheduledWorkouts: [ScheduledWorkout]?

    init(id: UUID = UUID(), name: String, notes: String? = nil, clonedFromWorkoutId: UUID? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = .now
        self.clonedFromWorkoutId = clonedFromWorkoutId
        self.updatedAt = .now
        self.deletedAt = nil
    }

    /// Locked while any live session — in-progress, paused, finished, or abandoned —
    /// references this workout, since restructuring it afterward would corrupt that
    /// history's meaning. Only the structure: the name and description stay editable,
    /// because neither changes what a past session did. Deleted sessions don't count, so
    /// clearing a workout's history from the History tab unlocks it again. Computed, not stored, so it can never go
    /// stale. Use `WorkoutCloningService` to get an editable copy once locked.
    var isLocked: Bool {
        sessions.contains { $0.deletedAt == nil }
    }

    /// Overrides the `SyncableModel` default rather than adding a second call site
    /// everywhere a workout changes — every edit already ends by calling this (directly,
    /// or through `section.markDirty(); workout?.markDirty()`), so it's the one place
    /// that can notice "this published workout just changed" without touching the other
    /// 46-odd call sites in `WorkoutEditingService` alone. See `SharePublishScheduler`.
    func markDirty() {
        updatedAt = .now
        SharePublishScheduler.shared.scheduleIfPublished(self)
    }

    var sortedSections: [WorkoutSection] {
        sections
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Derived, not stored: a stored flag would need perfect invalidation on every
    /// section insert/type-change/delete. This is cheap since `sections` is already
    /// what's rendered.
    var displayType: WorkoutDisplayType {
        let types = Set(sortedSections.map(\.sectionType))
        if types.isEmpty { return .empty }
        if types == [.time] { return .time }
        if types == [.rep] { return .rep }
        if types == [.emom] { return .emom }
        if types == [.amrap] { return .amrap }
        return .mixed
    }

    /// Short label for list rows, read straight off the section composition. Every
    /// workout is the same kind of thing now, so there is no prefix left to add.
    var listTypeLabel: String {
        switch displayType {
        case .time: return "Follow Along"
        case .rep: return "Rep"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        case .empty: return "Empty"
        case .mixed: return "Mixed"
        }
    }
}
