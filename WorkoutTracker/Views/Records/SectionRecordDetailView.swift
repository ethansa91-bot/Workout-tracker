import SwiftUI
import SwiftData

/// The record page for an EMOM or AMRAP section: the standing round count, a way to
/// correct it upward, and the dated progression behind it.
///
/// Deliberately not a branch inside `PersonalRecordEditView`. That screen is built around
/// resolving an exercise against its equipment, execution type and tracking mode, and a
/// section record has none of those — every one of its controls would be inert here.
struct SectionRecordDetailView: View {
    let record: PersonalRecord

    @Environment(\.modelContext) private var context

    /// nil until the stepper is touched, so the page shows the live record until the user
    /// actually proposes something.
    @State private var draft: Int?

    private var value: Int { draft ?? record.reps ?? 0 }

    /// The same best-only rule every record here follows: a lighter week can't quietly
    /// overwrite a better one. Correcting a record downward means deleting it from the
    /// Records list, exactly as it does for an exercise record.
    private var canSave: Bool {
        PersonalRecordQueries.sectionBeats(record: record, value: value)
    }

    private var title: String {
        record.sectionRecordName ?? record.sectionRecordKind?.fallbackSectionName ?? "Section Record"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Text("Rounds")
                    Spacer()
                    Button {
                        draft = max(0, value - 1)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    Text("\(value)")
                        .monospacedDigit()
                        .foregroundStyle(Color.appRust)
                        .frame(minWidth: 44)
                    Button {
                        draft = value + 1
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .foregroundStyle(Color.appAccent)
                .formRow()
            } header: {
                FormSectionHeader(record.sectionRecordKind?.pillLabel ?? "Record")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("Save")
                        .foregroundStyle(canSave ? Color.appAccent : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.appAccent.opacity(0.25))
                .disabled(!canSave)
                .formRow()
            } footer: {
                FormSectionFooter("Save unlocks once the value beats the current record.")
            }

            historySection
        }
        .fullBleedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            PushedTitleBand(title: title)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            // A record carries no achievement date of its own, so `updatedAt` is the best
            // stamp available — the same one `setSectionRecord` files superseded values
            // under. Not swipe-deletable: removing the record itself is the Records
            // list's swipe, and doing it here would leave the page editing nothing.
            historyRow(
                text: PersonalRecordFormatting.summary(record),
                date: record.updatedAt,
                isCurrent: true
            )
            // Already filtered of tombstones and sorted newest first by the getter.
            ForEach(record.history) { entry in
                historyRow(
                    text: PersonalRecordFormatting.summary(entry),
                    date: entry.achievedAt,
                    isCurrent: false
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        SyncDeletion.delete(entry, context: context)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            FormSectionHeader("Record Progression")
        } footer: {
            FormSectionFooter("Each time this record is beaten — here or at the end of a workout — the value it replaced is kept with the date it was set.")
        }
    }

    private func historyRow(text: String, date: Date, isCurrent: Bool) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.appInk)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let groupID = record.sectionRecordGroupID, let kind = record.sectionRecordKind else { return }
        PersonalRecordQueries.setSectionRecord(
            groupID: groupID,
            name: record.sectionRecordName ?? title,
            kind: kind,
            value: value,
            existing: record,
            context: context
        )
        draft = nil
    }
}
