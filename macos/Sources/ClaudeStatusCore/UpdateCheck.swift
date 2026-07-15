import Foundation

/// Manual "Check for Updates" support. Pure logic only (version parsing/comparison
/// and endpoint constants) so it is unit-testable; the actual network call lives in
/// the UI layer and fires ONLY when the user clicks the menu item — the app makes no
/// network requests on its own (see the offline promise in the README).
public enum UpdateCheck {

    /// GitHub repo the releases live in.
    public static let repo = "merve/claude-traffic-light"

    /// Endpoint answering with the latest release (`tag_name`, `html_url`).
    public static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    /// Where to send the user when a newer version exists (also the fallback when
    /// the API response carries no `html_url`).
    public static var releasesPage: URL {
        URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    /// Numeric components of a version string. Tolerates a leading "v" and ignores
    /// anything after a pre-release/build separator ("1.2.0-beta.1" → [1,2,0]).
    /// Returns nil when there is no leading numeric component at all.
    public static func parse(_ version: String) -> [Int]? {
        var s = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        s = s.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? s
        let parts = s.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    /// True when `latest` is strictly newer than `current`. Unparseable input is
    /// never "newer" — a malformed tag or a dev build without a version must not
    /// nag the user with a phantom update.
    public static func isNewer(latest: String, current: String) -> Bool {
        guard let l = parse(latest), let c = parse(current) else { return false }
        let n = max(l.count, c.count)
        for i in 0..<n {
            let li = i < l.count ? l[i] : 0
            let ci = i < c.count ? c[i] : 0
            if li != ci { return li > ci }
        }
        return false
    }

    /// Extracts (tagName, htmlURL) from a GitHub "latest release" JSON payload.
    /// Returns nil when the payload has no usable tag.
    public static func parseLatestRelease(json data: Data) -> (tag: String, url: URL)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String, !tag.isEmpty else { return nil }
        let url = (obj["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        return (tag, url)
    }
}
