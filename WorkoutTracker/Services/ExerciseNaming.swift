import Foundation

/// How an exercise is named once a side or an execution type is in play:
/// `"Push Up, Explosive"`, `"Split Squat, Left"`, `"Split Squat, Left, Slow"`.
///
/// One helper because the name is composed in a dozen places — the builder's rows, three
/// runners, the scrub strip, the all-exercises panel, history — and they have to agree.
/// They didn't before this existed: each had its own `stepTitle`/`chipTitle` switch, four
/// byte-identical copies of the same three-case function.
///
/// The comma form is deliberate and already established: `TimeSessionRunnerView` has
/// spoken cues this way since execution types shipped, so what the app says out loud and
/// what it puts on screen now come from the same rule.
enum ExerciseNaming {
    /// The separator, in one place so a later change can't apply to half the app.
    private static let separator = ", "

    /// A name that's already resolved — a snapshot, or "Rest".
    ///
    /// Side comes before execution type because it says *which* exercise this is, while the
    /// type says *how* it's performed — "Split Squat, Left, Slow" reads as one thing done
    /// one way, where the other order reads as two afterthoughts.
    static func title(_ base: String, side: SetSide? = nil, executionType: ExecutionType?) -> String {
        var result = base
        if let side {
            result += separator + side.longLabel
        }
        if let executionType, !executionType.name.isEmpty {
            result += separator + executionType.name
        }
        return result
    }

    /// The usual case. `displayName`, not `name`: this is for a person reading the screen,
    /// so a personal label wins — the opposite of the export, where a parser reads the
    /// string and needs the catalog name.
    static func title(_ exercise: Exercise?, side: SetSide? = nil, executionType: ExecutionType?, fallback: String = "Exercise") -> String {
        title(exercise?.displayName ?? fallback, side: side, executionType: executionType)
    }
}
