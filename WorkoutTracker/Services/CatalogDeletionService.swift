import Foundation
import SwiftData

enum CatalogDeletionError: LocalizedError {
    case inUse(String)

    var errorDescription: String? {
        switch self {
        case .inUse(let reason): return reason
        }
    }
}

/// Whether a catalog row can be removed, and why not.
///
/// Deleting here is a tombstone (`SyncDeletion`) and nothing repoints references at
/// anything else — a soft-deleted exercise drops out of the Library while every
/// `RepSectionExercise.exercise` still resolves to it. So a row that is still referenced
/// has to be refused up front rather than left to dangle.
enum CatalogDeletionService {

    // MARK: - Exercise

    /// `nil` when the exercise can be deleted; otherwise the sentence explaining what is
    /// holding it, shown under the disabled button.
    static func deletionBlockReason(for exercise: Exercise) -> String? {
        // A Get Ready step has no exercise, so those never count. Entries and their
        // sections are both soft-deleted, so both tombstones have to be filtered or a
        // removed section would keep reporting its exercises as used.
        let sections = liveSections(using: exercise)
        let workoutCount = sections.filter { $0.workout != nil }.count
        let templateCount = sections.count - workoutCount

        var parts: [String] = []
        if workoutCount > 0 { parts.append(count(workoutCount, "workout")) }
        if templateCount > 0 { parts.append(count(templateCount, "section template")) }
        if !parts.isEmpty {
            return "Used in \(parts.joined(separator: " and ")). Remove it there first."
        }

        if !live(exercise.setLogs).isEmpty {
            return "This exercise has logged sets behind it. Clear that history first."
        }
        if !live(exercise.personalRecords).isEmpty || !live(exercise.personalRecordEntries).isEmpty {
            return "This exercise has a personal record. Delete the record first."
        }
        return nil
    }

    static func delete(_ exercise: Exercise, context: ModelContext) throws {
        // Re-checked rather than trusted: the button was drawn before the confirmation,
        // and a session could have started in between.
        if let reason = deletionBlockReason(for: exercise) { throw CatalogDeletionError.inUse(reason) }
        SyncDeletion.delete(exercise, context: context)
        try context.save()
    }

    /// Every live section that references this exercise, whichever of the three entry
    /// types it goes through. Deduplicated, since one section can use it more than once.
    private static func liveSections(using exercise: Exercise) -> [WorkoutSection] {
        var sections: [UUID: WorkoutSection] = [:]

        func collect(_ section: WorkoutSection?) {
            guard let section, section.deletedAt == nil else { return }
            sections[section.id] = section
        }

        for entry in live(exercise.repSectionExercises) { collect(entry.section) }
        for step in live(exercise.timeSectionSteps) { collect(step.section) }
        for entry in live(exercise.sectionExerciseEntries) { collect(entry.section) }
        return Array(sections.values)
    }

    // MARK: - Equipment

    static func deletionBlockReason(for equipment: Equipment) -> String? {
        let attached = equipment.exercises.filter { $0.deletedAt == nil }
        if !attached.isEmpty {
            let names = attached.prefix(3).map(\.displayName).joined(separator: ", ")
            let suffix = attached.count > 3 ? " and \(attached.count - 3) more" : ""
            return "Attached to \(count(attached.count, "exercise")) (\(names)\(suffix)). Remove it there first."
        }
        if !live(equipment.repSectionExercises).isEmpty {
            return "A workout picked this as its equipment. Change that first."
        }
        if !live(equipment.setLogs).isEmpty {
            return "This equipment has logged sets behind it. Clear that history first."
        }
        if !live(equipment.personalRecords).isEmpty || !live(equipment.personalRecordEntries).isEmpty {
            return "This equipment has a personal record. Delete the record first."
        }
        return nil
    }

    static func delete(_ equipment: Equipment, context: ModelContext) throws {
        if let reason = deletionBlockReason(for: equipment) { throw CatalogDeletionError.inUse(reason) }
        // `weightCombos` cascade, so they need no separate pass.
        SyncDeletion.delete(equipment, context: context)
        try context.save()
    }

    // MARK: - Helpers

    private static func live<T: SyncableModel>(_ models: [T]?) -> [T] {
        (models ?? []).filter { $0.deletedAt == nil }
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
