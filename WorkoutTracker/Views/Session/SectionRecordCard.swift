import SwiftUI
import SwiftData

/// "How many rounds did you get?" — the post-workout card that turns an EMOM or AMRAP
/// section's round count into a personal record.
///
/// Nothing here is saved yet: the number comes off a counter tapped mid-effort, so a
/// miscount is likely enough that it deserves a correction pass before it becomes a
/// record. This card only edits a draft — `drafts`, owned by `SessionSummaryView` — and
/// the actual commit happens once, for every candidate, when that screen's Done button is
/// tapped. `SectionResultService.commitCorrectedResult` is what makes it real, and only
/// upward: a bad day can't overwrite a good one. Fixing an overcount still means deleting
/// the record from the Records tab, the same rule every record here follows.
///
/// Committing is also what promotes the section: the first record locks its structure and
/// files a copy in the templates list, so the benchmark can be dropped into any workout
/// and keep feeding the one history. That lives in `SectionResultService.promote`.
struct SectionRecordCard: View {
    let session: WorkoutSession
    let context: ModelContext
    /// Keyed by `recordGroupID`. Owned by `SessionSummaryView` so it can read the final,
    /// possibly-corrected values at Done-tap time — this card never writes a record
    /// itself.
    @Binding var drafts: [UUID: Int]

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Section Records").font(.headline)
                Text("Rounds you got. Adjust if the count is off — saved as your record when you tap Done below.")
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                ForEach(candidates) { candidate in
                    row(candidate)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .cardStyle(cornerRadius: 14)
        }
    }

    /// The best pass of every tracked section run this session. `SectionResultService`
    /// owns the grouping so the card and anything else reading results can't disagree
    /// about which attempt counts.
    private var candidates: [SectionResultLog] { SectionResultService.bestResults(in: session) }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ candidate: SectionResultLog) -> some View {
        if let groupID = candidate.recordGroupID {
            let existing = PersonalRecordQueries.sectionRecord(groupID: groupID, context: context)
            let draft = drafts[groupID] ?? candidate.value
            let willImprove = PersonalRecordQueries.sectionBeats(record: existing, value: draft)

            VStack(alignment: .leading, spacing: 6) {
                Text(PersonalRecordFormatting.sectionSourceLabel(name: candidate.displayName, kind: candidate.sectionType))
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)

                HStack(spacing: 10) {
                    Button {
                        step(groupID, to: draft - 1)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.appAccent)
                    .disabled(draft <= 0)

                    Text(PersonalRecordFormatting.sectionSummary(draft))
                        .font(.subheadline)
                        .foregroundStyle(Color.appRust)
                        .monospacedDigit()
                        .frame(minWidth: 72)

                    Button {
                        step(groupID, to: draft + 1)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.appAccent)

                    Spacer(minLength: 8)

                    // A preview of what Done will do with this number, not a control of
                    // its own — there's nothing to tap here, since nothing commits until
                    // the summary screen's own Done button does.
                    if willImprove {
                        Label("New record", systemImage: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appAccent)
                    }
                }

                if let best = existing?.reps {
                    Text("Best \(PersonalRecordFormatting.sectionSummary(best))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Editing

    private func step(_ groupID: UUID, to value: Int) {
        drafts[groupID] = max(0, value)
    }
}
