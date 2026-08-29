import SwiftUI

/// Field-by-field, mine against theirs, for one item that exists on both sides.
///
/// Only differing fields are listed. Showing everything would bury the three lines that
/// actually differ under a dozen that don't, and the decision being made here is about
/// exactly those three.
struct CatalogConflictDetailView: View {
    let subject: SharedImportReviewView.Comparison

    @Environment(\.dismiss) private var dismiss
    @State private var resolution: CatalogResolution

    init(subject: SharedImportReviewView.Comparison) {
        self.subject = subject
        _resolution = State(initialValue: subject.current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(subject.differences) { difference in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(difference.field)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appInkMuted)
                            comparisonRow("Yours", difference.mine, isChosen: resolution != .useTheirs)
                            comparisonRow("Theirs", difference.theirs, isChosen: resolution != .keepMine)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Differences")
                } footer: {
                    Text(footer)
                }

                Section {
                    picker(.merge, "Merge both", "Keeps your version and adds anything theirs has that yours doesn't.")
                    picker(.keepMine, "Keep mine", "Uses your version as-is. Nothing about it changes.")
                    picker(.useTheirs, "Use theirs", "Replaces your version's details with theirs.")
                } header: {
                    Text("What to do")
                }
            }
            .themedListBackground()
            .navigationTitle(subject.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        subject.apply(resolution)
                        dismiss()
                    }
                }
            }
        }
    }

    private var footer: String {
        let name = subject.localName.map { "“\($0)”" } ?? "your version"
        return "This matched \(name) in your library. Whichever you pick, it stays the same item — every workout and logged set that already uses it keeps working."
    }

    @ViewBuilder
    private func comparisonRow(_ side: String, _ value: String, isChosen: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(side)
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(isChosen ? Color.appInk : Color.appInkMuted)
                .strikethrough(!isChosen, color: Color.appInkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func picker(_ option: CatalogResolution, _ title: String, _ detail: String) -> some View {
        Button {
            resolution = option
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: resolution == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(resolution == option ? Color.appAccent : Color.appInkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.appInk)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}
