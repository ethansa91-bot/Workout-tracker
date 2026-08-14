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

/// The kind chosen at creation time, which governs how many/which sections the workout
/// is allowed to hold. Distinct from `displayType` below, which is purely derived
/// from the sections that happen to exist (for icons/labels) and never restricts
/// anything.
enum WorkoutKind: String, Codable {
    case personalized, byTime, byRep
}

@Model
final class Workout: SyncableModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var clonedFromWorkoutId: UUID?
    var kindRaw: String = WorkoutKind.personalized.rawValue
    var isArchived: Bool = false
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var remoteSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSection.workout)
    var sections: [WorkoutSection] = []

    /// Deny, not cascade: a workout with sessions is history and must not be able to
    /// vanish out from under them via a careless local delete.
    @Relationship(deleteRule: .deny, inverse: \WorkoutSession.workout)
    var sessions: [WorkoutSession] = []

    init(id: UUID = UUID(), name: String, notes: String? = nil, clonedFromWorkoutId: UUID? = nil, kind: WorkoutKind = .personalized) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = .now
        self.clonedFromWorkoutId = clonedFromWorkoutId
        self.kindRaw = kind.rawValue
        self.updatedAt = .now
        self.deletedAt = nil
        self.isDirty = true
        self.remoteSyncedAt = nil
    }

    var kind: WorkoutKind {
        get { WorkoutKind(rawValue: kindRaw) ?? .personalized }
        set { kindRaw = newValue.rawValue }
    }

    /// Locked the instant any session — in-progress, paused, finished, or abandoned —
    /// has ever referenced this workout, since editing afterward would corrupt that
    /// history's meaning. Computed, not stored, so it can never go stale. Use
    /// `WorkoutCloningService` to get an editable copy once locked.
    var isLocked: Bool {
        !sessions.isEmpty
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

    /// Short label for list rows. By Time/By Reps show their kind's own label
    /// ("Follow Along"/"Rep"), with ": Empty" appended before their one section exists.
    /// Personalized appends its section composition — "Personalized: Follow Along" for
    /// one made entirely of Follow Along sections, "Personalized: Mixed" once it has
    /// several kinds, "Personalized: Empty" before it has any.
    var listTypeLabel: String {
        switch kind {
        case .byTime: return displayType == .empty ? "Follow Along: Empty" : "Follow Along"
        case .byRep: return displayType == .empty ? "Rep: Empty" : "Rep"
        case .personalized:
            switch displayType {
            case .time: return "Personalized: Follow Along"
            case .rep: return "Personalized: Rep"
            case .emom: return "Personalized: EMOM"
            case .amrap: return "Personalized: AMRAP"
            case .empty: return "Personalized: Empty"
            case .mixed: return "Personalized: Mixed"
            }
        }
    }
}
