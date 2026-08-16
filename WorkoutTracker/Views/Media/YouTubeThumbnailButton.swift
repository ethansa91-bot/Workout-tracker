import SwiftUI

/// A YouTube thumbnail that opens a full, unmuted, controlled player on tap — the
/// static-preview half of `ExerciseMediaView`, factored out so it also works from a
/// raw, not-yet-saved URL string (the exercise edit form's live preview while typing).
struct YouTubeThumbnailButton: View {
    let urlString: String
    var title: String = "Video"

    @State private var showingPlayer = false

    var body: some View {
        if let videoID = YouTubeURL.videoID(from: urlString) {
            Button {
                showingPlayer = true
            } label: {
                ZStack {
                    if let thumbnailURL = YouTubeURL.thumbnailURL(for: urlString) {
                        AsyncImage(url: thumbnailURL) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingPlayer) {
                NavigationStack {
                    YouTubePlayerView(videoID: videoID, maxSeconds: nil, muted: false, showsControls: true)
                        .navigationTitle(title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingPlayer = false }
                            }
                        }
                }
            }
        }
    }
}
