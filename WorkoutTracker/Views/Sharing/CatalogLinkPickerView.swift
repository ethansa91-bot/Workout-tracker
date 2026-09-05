import SwiftUI

/// Points an incoming item at something already in the library.
///
/// This is the answer to "their *Barbell Bench* is my *Bench Press*". Name matching is
/// exact-only, so without this every near-miss becomes a second row and the catalog
/// slowly fills with the same exercise under three spellings. Linking adds nothing at
/// all — the downloaded workout simply uses the row that's already there.
struct CatalogLinkPickerView: View {
    let subject: SharedImportReviewView.Linking

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [CatalogCandidate] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return subject.candidates }
        return subject.candidates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty {
                    ContentUnavailableView(
                        "Nothing Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No item in your library matches “\(search)”.")
                    )
                } else {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, candidate in
                        Button {
                            subject.apply(.link(candidate.id))
                            dismiss()
                        } label: {
                            HStack {
                                Text(candidate.name).foregroundStyle(Color.appInk)
                                Spacer()
                                if case .link(let selected) = subject.current, selected == candidate.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        // Matches the Library list's own row — this had none at all,
                        // making it the shortest, hardest-to-tap row in the app.
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .fullBleedRow(isLast: index == matches.count - 1)
                    }
                }
            }
            .fullBleedList()
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    PushedTitleBand(
                        title: "Link “\(subject.title)”",
                        subtitle: "Pick what this already is in your library. Nothing new gets added."
                    )
                    InlineSearchField(prompt: "Search your library", text: $search)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
