import SwiftUI

/// Opens an exercise's video in a full, unmuted player — shown only when the media box
/// above it has left the video with no way in.
///
/// `ExerciseMediaView.autoplayWorkout` plays the video when autoplay is on, and falls
/// back to a tappable thumbnail when there's no picture to show instead. But with
/// autoplay off *and* a picture present it renders a plain, inert `Image`, and the
/// video is unreachable for the rest of the workout — which is also not what Settings
/// promises ("shows a tappable still instead"). This is the way back to it.
///
/// Deliberately conditional rather than always-on: where the box is already playing the
/// video or already offers it on tap, a second control for the same thing is noise.
struct ExerciseVideoButton: View {
    let exercise: Exercise

    @State private var showingPlayer = false

    /// Read through `@AppStorage` rather than `AppSettings` for the same reason
    /// `ExerciseMediaView` does — toggling the setting redraws what's on screen instead
    /// of waiting for the next exercise.
    @AppStorage("settings.workoutVideoAutoplay") private var autoplayVideo = true

    private var videoID: String? {
        exercise.videoURL.flatMap(YouTubeURL.videoID(from:))
    }

    /// Offline is excluded because the player wouldn't load anyway — the button would
    /// promise something it can't deliver.
    private var isUnreachable: Bool {
        videoID != nil
            && NetworkReachability.shared.isOnline
            && !autoplayVideo
            && ExerciseMediaView.hasPicture(exercise)
    }

    var body: some View {
        if isUnreachable, let videoID {
            Button {
                showingPlayer = true
            } label: {
                // Same shape and type as the Description button beside it; the video's
                // own tint, matching the library's video button.
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                    Text("Play video")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(Color.appDanger)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingPlayer) {
                NavigationStack {
                    // Uncapped, unmuted, with controls — the opposite of the muted
                    // preview loop the runner plays when autoplay is on.
                    YouTubePlayerView(videoID: videoID, maxSeconds: nil, muted: false, showsControls: true)
                        .navigationTitle(exercise.displayName)
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
