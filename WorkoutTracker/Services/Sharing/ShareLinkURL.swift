import Foundation

/// The link form of a share code.
///
/// A custom scheme rather than a universal link, because universal links need a domain
/// with an `apple-app-site-association` file behind it and there isn't one. The trade-off
/// is real and worth knowing: Messages and Mail don't reliably turn a `workouttracker://`
/// URL into something tappable, and it does nothing at all on a device without the app.
/// So everywhere a link is shared, the readable code goes with it — see
/// `SharingHomeView.shareMessage`. The link is the fast path, not the only path.
///
/// `parse` switches on the scheme so an `https://` form can be added later without
/// touching a single call site.
enum ShareLinkURL {
    static let scheme = "workouttracker"

    private static let followHost = "follow"
    private static let codeQueryItem = "code"

    enum Route: Equatable {
        case follow(code: String)
    }

    /// `workouttracker://follow?code=ACDE3F7K` — normalized, so the URL never carries the
    /// display hyphen that `ShareCode.format` adds.
    static func follow(code: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = followHost
        components.queryItems = [URLQueryItem(name: codeQueryItem, value: ShareCode.normalize(code))]
        // The components above are all fixed or normalized to the code alphabet, so this
        // can't fail — but a crash on a share button is never worth a force unwrap.
        return components.url ?? URL(string: "\(scheme)://\(followHost)")!
    }

    /// Returns nil for anything that isn't a link this app issued, including a link whose
    /// code couldn't possibly be real — rejecting it here saves a pointless round trip to
    /// CloudKit before the user is told it's malformed.
    static func parse(_ url: URL) -> Route? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == followHost else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let raw = components?.queryItems?.first(where: { $0.name == codeQueryItem })?.value else {
            return nil
        }

        let normalized = ShareCode.normalize(raw)
        guard ShareCode.isPlausible(normalized) else { return nil }
        return .follow(code: normalized)
    }
}
