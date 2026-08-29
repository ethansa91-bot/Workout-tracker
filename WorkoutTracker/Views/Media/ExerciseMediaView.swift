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
    /// Overrides `Self.height` — used by EMOM/AMRAP's grid, where each cell's media
    /// must fit an exact row height (2 rows visible without scrolling) rather than the
    /// fixed 220pt every other call site uses.
    var height: CGFloat = ExerciseMediaView.height
    /// Fill the available width and take height from the 16:9 ratio, rather than being
    /// sized by `height`. The single-exercise runners use this so the media is as large
    /// as the column allows; the EMOM/AMRAP grids don't, since their cells need an exact
    /// row height.
    var fillsWidth: Bool = false

    /// Set when YouTube reports the video can't be embedded (common for Shorts, even
    /// when the regular link plays fine) — falls back to the photo instead of leaving
    /// YouTube's own error overlay on screen. Call sites key this view with
    /// `.id(exercise.id)`, so this resets naturally when the exercise changes.
    @State private var videoFailed = false

    /// Read through `@AppStorage` rather than `AppSettings` so toggling the setting
    /// redraws whatever is on screen instead of waiting for the next step.
    @AppStorage("settings.workoutVideoAutoplay") private var autoplayVideo = true

    private var isOnline: Bool { NetworkReachability.shared.isOnline }

    private var videoID: String? {
        exercise.videoURL.flatMap(YouTubeURL.videoID(from:))
    }

    /// Whether this exercise has anything to show at all, so a caller can drop the box
    /// entirely rather than reserving space for the "No photo/video available"
    /// placeholder. Deliberately mirrors the three sources `photoOrFallback` and the
    /// video branches check, so the two can't disagree about what "has media" means.
    @MainActor
    static func hasMedia(_ exercise: Exercise) -> Bool {
        if exercise.videoURL.flatMap(YouTubeURL.videoID(from:)) != nil { return true }
        if exercise.imageAssetName != nil { return true }
        // `exists` rather than `load`: this is a yes/no question, and callers ask it from
        // inside a body that re-renders once a second during a Follow Along step —
        // decoding the JPEG to answer it made that a per-second disk read and decode.
        if let fileName = exercise.generatedImageFileName,
           GeneratedExerciseImageStore.exists(fileName: fileName) { return true }
        return false
    }

    /// Whether there's a picture on the device, so the video branches know whether
    /// falling back would land on something worth showing.
    ///
    /// Static as well as instance: `ExerciseVideoButton` has to answer the same
    /// question from outside — a picture is exactly what makes the video branches fall
    /// through and leaves the video with no way in.
    @MainActor
    static func hasPicture(_ exercise: Exercise) -> Bool {
        if exercise.imageAssetName != nil { return true }
        if let fileName = exercise.generatedImageFileName {
            return GeneratedExerciseImageStore.exists(fileName: fileName)
        }
        return false
    }

    private var hasLocalPicture: Bool { Self.hasPicture(exercise) }

    private var localImage: UIImage? {
        guard let fileName = exercise.generatedImageFileName else { return nil }
        return GeneratedExerciseImageStore.load(fileName: fileName)
    }

    private static let height: CGFloat = 220
    /// A normal 16:9 video rectangle derived from `height`, rather than always
    /// stretching to the full screen width — on phones this is wider than the screen
    /// anyway so it has no visible effect, but on bigger screens (iPad) the box stays a
    /// sensible video-sized rectangle instead of one long thin bar. Applies identically
    /// whether showing video, a photo, or the text fallback, since all three share this
    /// same outer frame.
    private var maxWidth: CGFloat { height * 16 / 9 }

    var body: some View {
        if fillsWidth {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Ratio drives the height, so the box grows with the column instead of
                // being pinned to a fixed 220pt and capped short of the edges.
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity)
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxWidth: maxWidth)
                .frame(height: height)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .autoplayWorkout(let maxSeconds):
            if isOnline, autoplayVideo, let videoID, !videoFailed {
                YouTubePlayerView(videoID: videoID, maxSeconds: maxSeconds, muted: true, showsControls: false) {
                    videoFailed = true
                }
            } else if isOnline, !videoFailed, !hasLocalPicture, videoID != nil, let urlString = exercise.videoURL {
                // Autoplay off and no picture to fall back on: show the edit form's
                // static thumbnail, still tappable, rather than telling someone their
                // video-only exercise has no media. Costs one image, not a web view.
                YouTubeThumbnailButton(urlString: urlString, title: exercise.displayName)
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
            // Media only — the exercise's description lives under this box
            // (`ExerciseDescriptionView`), not inside it, so it shows whether or not
            // there's a photo to go with it.
            Text("No photo/video available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
