import SwiftUI

/// The fixed-size "defined space" for an exercise's media, reused everywhere it's
/// shown: the edit form (static thumbnail, tap to open) and every active-workout
/// session runner (muted autoplay, capped, offline-aware — or photo-only for EMOM/AMRAP).
/// Content precedence — video (where applicable), then photo, then a text fallback —
/// is identical across modes; only how/whether video plays differs.
enum ExerciseMediaMode {
    /// Edit form: a static YouTube thumbnail: tapping opens a full, unmuted, controlled
    /// player in a sheet.
    case staticThumbnail
    /// Active workout: muted autoplay capped at `maxSeconds`, looping if the video ends
    /// sooner — falls back to a photo when offline or there's no video.
    case autoplayWorkout(maxSeconds: Double)
    /// Photo/fallback only, never video — EMOM and AMRAP show every exercise in the
    /// round at once, where several simultaneous autoplaying videos would be too much.
    case photoOnly
}

struct ExerciseMediaView: View {
    let exercise: Exercise
    var mode: ExerciseMediaMode

    /// Set when YouTube reports the video can't be embedded (common for Shorts, even
    /// when the regular link plays fine) — falls back to the photo instead of leaving
    /// YouTube's own error overlay on screen. Call sites key this view with
    /// `.id(exercise.id)`, so this resets naturally when the exercise changes.
    @State private var videoFailed = false

    private var isOnline: Bool { NetworkReachability.shared.isOnline }

    private var videoID: String? {
        exercise.videoURL.flatMap(YouTubeURL.videoID(from:))
    }

    private var localImage: UIImage? {
        guard let fileName = exercise.generatedImageFileName else { return nil }
        return GeneratedExerciseImageStore.load(fileName: fileName)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .autoplayWorkout(let maxSeconds):
            if isOnline, let videoID, !videoFailed {
                YouTubePlayerView(videoID: videoID, maxSeconds: maxSeconds, muted: true, showsControls: false) {
                    videoFailed = true
                }
            } else {
                photoOrFallback
            }
        case .staticThumbnail:
            if videoID != nil, let urlString = exercise.videoURL {
                YouTubeThumbnailButton(urlString: urlString, title: exercise.displayName)
            } else {
                photoOrFallback
            }
        case .photoOnly:
            photoOrFallback
        }
    }

    @ViewBuilder
    private var photoOrFallback: some View {
        if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let assetName = exercise.imageAssetName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Text("No visual data found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
