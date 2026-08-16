import SwiftUI
import YouTubeiOSPlayerHelper

/// Thin SwiftUI wrapper around `YTPlayerView` — YouTube's own official iOS embed
/// helper (github.com/youtube/youtube-ios-player-helper), added as a dependency after
/// a hand-rolled `WKWebView` + custom JS implementation kept hitting embed errors
/// (152/153) that this library, built and maintained by YouTube for exactly this
/// purpose, handles correctly out of the box.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    /// Pauses playback after this many seconds, looping first if the video ends sooner.
    /// `nil` plays normally with no cap or loop (used for the user-initiated full player).
    var maxSeconds: Double? = 30
    var muted: Bool = true
    var showsControls: Bool = false
    /// Called when YouTube reports the video can't be played embedded (e.g. many Shorts
    /// block iframe embedding even though the regular link works) — callers should fall
    /// back to a photo rather than leaving YouTube's own error overlay on screen.
    var onError: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(maxSeconds: maxSeconds, muted: muted, onError: onError)
    }

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.delegate = context.coordinator
        context.coordinator.playerView = playerView

        let playerVars: [String: Any] = [
            "autoplay": 1,
            "playsinline": 1,
            "controls": showsControls ? 1 : 0,
            "modestbranding": 1,
            "rel": 0,
            "iv_load_policy": 3,
            "fs": 0,
        ]
        playerView.load(withVideoId: videoID, playerVars: playerVars)
        return playerView
    }

    func updateUIView(_ uiView: YTPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: YTPlayerView, coordinator: Coordinator) {
        coordinator.invalidate()
        uiView.stopVideo()
    }

    @MainActor
    final class Coordinator: NSObject, YTPlayerViewDelegate {
        weak var playerView: YTPlayerView?
        private let maxSeconds: Double?
        private let muted: Bool
        private let onError: (() -> Void)?
        private var capTimer: Timer?
        private var hasStartedCapTimer = false

        init(maxSeconds: Double?, muted: Bool, onError: (() -> Void)?) {
            self.maxSeconds = maxSeconds
            self.muted = muted
            self.onError = onError
        }

        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            // YTPlayerView exposes no mute()/unMute() API, but does expose its
            // underlying `webView` — its embed template names the JS player instance
            // `player` (Sources/Assets/YTPlayerView-iframe-player.html), so mute by
            // calling straight into it.
            if muted {
                playerView.webView?.evaluateJavaScript("player.mute();")
            }
            playerView.playVideo()
        }

        func playerView(_ playerView: YTPlayerView, didChangeTo state: YTPlayerState) {
            switch state {
            case .ended:
                if maxSeconds != nil {
                    // Uncapped mode plays through to a natural end instead of looping.
                    playerView.seek(toSeconds: 0, allowSeekAhead: true)
                    playerView.playVideo()
                }
            case .playing:
                startCapTimerIfNeeded()
            default:
                break
            }
        }

        func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
            print("YouTubePlayerView: player error \(error)")
            onError?()
        }

        private func startCapTimerIfNeeded() {
            guard let maxSeconds, !hasStartedCapTimer else { return }
            hasStartedCapTimer = true
            capTimer = Timer.scheduledTimer(withTimeInterval: maxSeconds, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.playerView?.pauseVideo()
                }
            }
        }

        func invalidate() {
            capTimer?.invalidate()
            capTimer = nil
        }
    }
}
