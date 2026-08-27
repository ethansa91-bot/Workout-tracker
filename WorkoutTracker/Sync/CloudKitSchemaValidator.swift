#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData

/// Development-only schema check.
///
/// `initializeCloudKitSchema(options: .dryRun)` walks the entire model graph and reports
/// anything CloudKit can't mirror, naming the offending entity and property. That is the
/// detail an export `partialFailure` refuses to give — it reports that records failed,
/// not why — so this is the fastest route from "sync is broken" to a specific field.
///
/// Requires a signed-in iCloud account and blocks while it runs, so it is opt-in via the
/// `CK_VALIDATE=1` environment variable and never runs in a normal launch. Debug-only:
/// `initializeCloudKitSchema` must never be called in a shipping build.
enum CloudKitSchemaValidator {

    static func run() {
        var log: [String] = []
        func say(_ line: String) {
            log.append(line)
            print("CKSCHEMA \(line)")
        }

        say("=== CloudKit schema dry run ===")
        say("container: \(CloudKitContainer.identifier)")

        let types: [any PersistentModel.Type] = [
            MuscleCategory.self, Muscle.self, Equipment.self, WeightCombo.self,
            ExerciseCategory.self, Exercise.self, Workout.self, WorkoutSection.self,
            TimeSectionStep.self, RepSectionExercise.self, SectionExerciseEntry.self,
            WorkoutSession.self, StepLog.self, SetLog.self, ExerciseSessionNote.self,
            PersonalRecord.self, PersonalRecordEntry.self,
            RecurringWorkoutSchedule.self, ScheduledWorkout.self,
            FollowedUser.self,
        ]
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
            say("FAILED to build managed object model")
            write(log)
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ckvalidate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A throwaway store, so validating can never touch the user's real data.
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("Validate.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: CloudKitContainer.identifier
        )

        let container = NSPersistentCloudKitContainer(name: "Validate", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            say("STORE LOAD FAILED: \(loadError)")
            write(log)
            return
        }
        say("store loaded — running dry run (needs a signed-in iCloud account)…")

        do {
            try container.initializeCloudKitSchema(options: [.dryRun])
            say("✅ DRY RUN PASSED — every entity is CloudKit-mappable.")
            say("The failure is in the data or the account, not the model graph.")
        } catch {
            say("❌ DRY RUN FAILED — this names the cause:")
            describe(error as NSError, indent: "  ", say: say)
        }

        try? FileManager.default.removeItem(at: directory)
        say("DONE")
        write(log)
    }

    /// Walks the whole error chain. CloudKit nests the useful part — the entity and
    /// property it choked on — several levels below the top-level description.
    private static func describe(_ error: NSError, indent: String, say: (String) -> Void, depth: Int = 0) {
        guard depth < 6 else { return }
        say("\(indent)\(error.domain) \(error.code): \(error.localizedDescription)")
        if let reason = error.localizedFailureReason, !reason.isEmpty {
            say("\(indent)  reason: \(reason)")
        }
        for (key, value) in error.userInfo.sorted(by: { $0.key < $1.key })
        where key != NSUnderlyingErrorKey && key != NSMultipleUnderlyingErrorsKey {
            say("\(indent)  \(key) = \(value)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            describe(underlying, indent: indent + "    ", say: say, depth: depth + 1)
        }
        if let multiple = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            for sub in multiple.prefix(5) {
                describe(sub, indent: indent + "    ", say: say, depth: depth + 1)
            }
        }
    }

    /// Also written to a file so the result survives the app being backgrounded, and can
    /// be pulled off the device without watching the console live.
    private static func write(_ log: [String]) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ckschema.txt")
        try? log.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
