import Foundation

/// What a link leads to, read from its address. It decides what the thing looks like in the jar:
/// a video still, a post, a newspaper clipping, a card of code, a cassette, a piece of map, a price
/// tag, a page of a document, or for any other site the luggage tag.
public enum LinkKind: String, CaseIterable, Sendable {
    case video, post, article, code, audio, place, product, document, page

    public static func of(_ url: URL) -> LinkKind {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        return rules.first { $0.matches(host: host, path: path) }?.kind ?? .page
    }

    /// `owner/repo` for a link into a code host, the part worth showing in a monospaced line.
    public static func repository(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        guard ["github.com", "gitlab.com", "codeberg.org", "bitbucket.org"].contains(where: { Rule.within(host, $0) }) else { return nil }
        let parts = url.path.split(separator: "/").prefix(2)
        return parts.count == 2 ? parts.joined(separator: "/") : nil
    }

    private struct Rule {
        let kind: LinkKind
        let domains: [String]
        /// Only addresses on these domains whose path starts like this.
        var path: String?

        func matches(host: String, path p: String) -> Bool {
            guard domains.contains(where: { Rule.within(host, $0) }) else { return false }
            return path.map { p.hasPrefix($0) } ?? true
        }

        /// The domain itself or any of its subdomains: `www.`, `m.`, `ru.` and the like.
        static func within(_ host: String, _ domain: String) -> Bool {
            host == domain || host.hasSuffix("." + domain)
        }
    }

    /// The first rule that matches wins, so the narrow ones come first: a map on google.com before
    /// documents on it, music on youtube.com before its videos, videos on vk.com before its posts.
    private static let rules: [Rule] = [
        Rule(kind: .place, domains: ["google.com", "google.ru"], path: "/maps"),
        Rule(kind: .place, domains: ["yandex.ru", "yandex.com"], path: "/maps"),
        Rule(kind: .place, domains: ["maps.google.com", "maps.apple.com", "2gis.ru", "2gis.com", "openstreetmap.org"]),
        Rule(kind: .audio, domains: ["music.youtube.com", "music.yandex.ru", "music.yandex.com", "spotify.com", "soundcloud.com",
                                     "music.apple.com", "podcasts.apple.com", "bandcamp.com", "zvuk.com"]),
        Rule(kind: .video, domains: ["vk.com"], path: "/video"),
        Rule(kind: .video, domains: ["vk.com"], path: "/clip"),
        Rule(kind: .video, domains: ["dzen.ru", "ok.ru"], path: "/video"),
        Rule(kind: .video, domains: ["youtube.com", "youtu.be", "vimeo.com", "rutube.ru", "twitch.tv", "tiktok.com", "vkvideo.ru"]),
        Rule(kind: .code, domains: ["github.com", "gitlab.com", "bitbucket.org", "codeberg.org", "stackoverflow.com", "stackexchange.com"]),
        Rule(kind: .document, domains: ["docs.google.com", "drive.google.com", "notion.so", "notion.site", "figma.com", "miro.com",
                                        "paper.dropbox.com"]),
        Rule(kind: .product, domains: ["ozon.ru", "wildberries.ru", "avito.ru", "market.yandex.ru", "lamoda.ru", "aliexpress.ru",
                                       "aliexpress.com", "amazon.com", "amazon.de", "amazon.co.uk", "amazon.fr", "ebay.com", "etsy.com"]),
        Rule(kind: .post, domains: ["linkedin.com", "t.me", "telegram.me", "x.com", "twitter.com", "vk.com", "facebook.com",
                                    "instagram.com", "threads.net", "reddit.com", "bsky.app", "mastodon.social", "pikabu.ru"]),
        Rule(kind: .article, domains: ["habr.com", "vc.ru", "dtf.ru", "medium.com", "substack.com", "dev.to", "wikipedia.org",
                                       "meduza.io", "lenta.ru", "rbc.ru", "kommersant.ru", "tproger.ru", "theverge.com",
                                       "arstechnica.com", "nytimes.com", "theguardian.com", "bbc.com", "bbc.co.uk"]),
    ]
}

extension Item {
    /// What the link leads to; nil for anything that is not a link.
    public var linkKind: LinkKind? {
        guard kind == .link else { return nil }
        return url.flatMap(URL.init(string:)).map(LinkKind.of) ?? .page
    }
}
