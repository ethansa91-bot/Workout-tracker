import Foundation

/// Extracts the 11-character video ID from a YouTube URL and builds thumbnail URLs.
/// Handles every shape seen in `catalog.json` (`youtube.com/shorts/<id>`,
/// `youtube.com/watch?v=<id>&pp=...`) plus `youtu.be/<id>` and `youtube.com/embed/<id>`
/// for whatever a user might paste into the edit form.
enum YouTubeURL {
    private static let idPattern = try! NSRegularExpression(
        pattern: #"(?:youtube\.com/(?:shorts|embed)/|youtube\.com/watch\?(?:.*&)?v=|youtu\.be/)([A-Za-z0-9_-]{11})"#
    )

    static func videoID(from urlString: String) -> String? {
        let range = NSRange(urlString.startIndex..., in: urlString)
        guard let match = idPattern.firstMatch(in: urlString, range: range),
              let idRange = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        return String(urlString[idRange])
    }

    static func thumbnailURL(for urlString: String) -> URL? {
        guard let id = videoID(from: urlString) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }
}
