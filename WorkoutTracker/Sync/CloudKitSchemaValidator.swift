#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData

/// Development-only schema tooling, in two modes.
///
/// **Check** (`CK_VALIDATE=1`) — `initializeCloudKitSchema(options: .dryRun)` walks the
/// entire model graph and reports anything CloudKit can't mirror, naming the offending
/// entity and property. That is the detail an export `partialFailure` refuses to give —
/// it reports that records failed, not why — so this is the fastest route from "sync is
/// broken" to a specific field.
///
/// **Create** (`CK_INIT_SCHEMA=1`) — the same call *without* `.dryRun`, which creates
/// every record type and field of the model graph in the Development environment.
///
/// ## Before every TestFlight build that added a model
///
/// Run `CK_INIT_SCHEMA=1`, then deploy to Production from the CloudKit Console. Any commit
/// adding a `@Model` type or a stored property needs this.
///
/// CloudKit only auto-creates a record type in Development, and only when a build actually
/// *writes a record of that type*; Production never auto-creates anything. So a type whose
/// write path isn't part of ordinary debug use never reaches Development either — and with
/// both environments then agreeing, "Deploy Schema Changes" greys out and reads as
/// "already deployed" when neither has ever heard of the type. That is exactly how
/// `FollowedUser` (written only by following someone via a share code) shipped to
/// TestFlight undeployed and blocked every export. Creating the schema from the model
/// rather than from data is what closes that hole.
///
/// Requires a signed-in iCloud account and a development-signed build, and blocks while it
/// runs, so both modes are opt-in and never run in a normal launch. Debug-only:
/// `initializeCloudKitSchema` must never be called in a shipping build.
enum CloudKitSchemaValidator {

    /// - Parameter createsSchema: `false` only reports; `true` writes the model graph to
    ///   the Development environment.
    static func run(createsSchema: Bool = false) {
        var log: [String] = []
        func say(_ line: String) {
            log.append(line)
            print("CKSCHEMA \(line)")
        }

        // Named in the log because the two modes are one flag apart and their outcomes
        // look alike — a dry run mistaken for a deploy is the failure this whole file
        // exists to prevent.
        say(createsSchema
            ? "=== CloudKit schema CREATE (Development) ==="
            : "=== CloudKit schema dry run (reports only, creates nothing) ===")
        say("container: \(CloudKitContainer.identifier)")

        let types: [any PersistentModel.Type] = [
            MuscleCategory.self, Muscle.self, Equipment.self, WeightCombo.self,
            ExerciseCategory.self, ExecutionType.self, Exercise.self,
            ProgressionGroup.self, ProgressionStep.self,
            WorkoutTag.self, Workout.self, WorkoutSection.self,
            TimeSectionStep.self, RepSectionExercise.self, SectionExerciseEntry.self,
            WorkoutSession.self, StepLog.self, SetLog.self, SectionResultLog.self, ExerciseSessionNote.self,
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
        say(createsSchema
            ? "store loaded — creating schema in Development (needs a signed-in iCloud account)…"
            : "store loaded — running dry run (needs a signed-in iCloud account)…")

        do {
            // The empty option set is the whole difference: `.dryRun` reports and creates
            // nothing, no options creates every record type and field on the server.
            try container.initializeCloudKitSchema(options: createsSchema ? [] : [.dryRun])
            if createsSchema {
                say("✅ SCHEMA CREATED in Development — every entity and property is now on the server.")
                say("NEXT: CloudKit Console → Schema → Deploy Schema Changes → Production.")
                say("Nothing has reached Production yet; this only touched Development.")
            } else {
                say("✅ DRY RUN PASSED — every entity is CloudKit-mappable. Nothing was created.")
                say("The failure is in the data, the account, or an undeployed schema — not the model graph.")
                say("If Production exports are failing, re-run with CK_INIT_SCHEMA=1 and then deploy.")
            }
        } catch {
            say(createsSchema
                ? "❌ SCHEMA CREATION FAILED — this names the cause:"
                : "❌ DRY RUN FAILED — this names the cause:")
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
