import Foundation

/// One thing handed to Conserva by a drop, a paste or the menu, before it is
/// sorted into a kind. The app reads these off a pasteboard; nothing here needs AppKit.
public enum Incoming: Equatable, Sendable {
    /// Plain text. It may turn out to be one or more links.
    case text(String)
    /// A web address, with the title the source offered, if any (a browser
    /// tab dragged out gives one).
    case webURL(URL, title: String?)
    /// A file from Finder or another app.
    case fileURL(URL)
    /// Picture data with no file behind it, such as a screenshot copied to the clipboard.
    case imageData(Data, fileExtension: String)
}

/// A new item that still has to be stored: `source` says what to copy into the shelf folder.
public struct Draft: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case none
        case copy(URL)
        case data(Data, fileExtension: String)
    }

    public var item: Item
    public var source: Source
}

public enum Intake {
    /// Extensions shown as a photo in the jar. Anything else is a file.
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp"]
    /// A slip shows one short line; the card shows the rest.
    public static let titleLength = 70

    public static func drafts(from incoming: [Incoming], now: Date = Date()) -> [Draft] {
        var out: [Draft] = []
        var seenLinks = Set<String>()
        func addLink(_ url: URL, title: String?) {
            let s = url.absoluteString
            guard seenLinks.insert(s).inserted else { return }
            let t = title.flatMap(cleanTitle) ?? Intake.title(forURL: url)
            out.append(Draft(item: Item(kind: .link, title: t, url: s, addedAt: now), source: .none))
        }
        for thing in incoming {
            switch thing {
            case .webURL(let url, let title):
                addLink(url, title: title)
            case .text(let raw):
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let links = links(in: trimmed) {
                    links.forEach { addLink($0, title: nil) }
                } else {
                    out.append(Draft(item: Item(kind: .text, title: title(forText: trimmed), text: trimmed, addedAt: now),
                                     source: .none))
                }
            case .fileURL(let url):
                let ext = url.pathExtension.lowercased()
                let kind: ItemKind = imageExtensions.contains(ext) ? .image : .file
                let name = url.lastPathComponent
                let title = kind == .image ? url.deletingPathExtension().lastPathComponent : name
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
                out.append(Draft(item: Item(kind: kind, title: title.isEmpty ? name : title, originalName: name,
                                            byteSize: size, addedAt: now),
                                 source: .copy(url)))
            case .imageData(let data, let ext):
                out.append(Draft(item: Item(kind: .image, title: imageTitle(at: now), byteSize: data.count, addedAt: now),
                                 source: .data(data, fileExtension: ext)))
            }
        }
        return out
    }

    /// The text is only links, separated by spaces or new lines: one link per address.
    /// Anything else in it, and it is a note.
    public static func links(in text: String) -> [URL]? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        var urls: [URL] = []
        for w in words {
            guard let u = webURL(w) else { return nil }
            urls.append(u)
        }
        return urls
    }

    /// `https://…` and `http://…`, and a bare `www.…` the way people copy it from a page.
    public static func webURL(_ s: String) -> URL? {
        var candidate = s
        if candidate.lowercased().hasPrefix("www.") { candidate = "https://" + candidate }
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// A host on this machine or the local network: pasting such a link must not make a request
    /// to it, as nothing public answers there and a page title is not worth the knock.
    public static func isPrivateHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        if host == "localhost" || [".local", ".localhost", ".lan", ".internal", ".home.arpa"].contains(where: host.hasSuffix) { return true }
        if host.contains(":") { return true }  // IPv6 literal
        // A name without a dot is an intranet one. No top-level domain is a number, so a numeric last part
        // is an IPv4 address in any of the spellings the resolver takes: 127.0.0.1, 127.1, 0x7f.1, 2130706433.
        guard let last = host.split(separator: ".").last, host.contains(".") else { return true }
        return last.allSatisfy(\.isNumber) || last.hasPrefix("0x")
    }

    /// A readable guess until the page title arrives: the last part of the
    /// path with dashes as spaces, or the site's name.
    public static func title(forURL url: URL) -> String {
        let host = displayHost(url)
        let last = url.path.split(separator: "/").last.map(String.init) ?? ""
        let decoded = last.removingPercentEncoding ?? last
        var words = decoded.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        if let dot = words.lastIndex(of: "."), words.distance(from: dot, to: words.endIndex) <= 5 {
            words = String(words[..<dot])
        }
        words = words.trimmingCharacters(in: .whitespaces)
        if words.isEmpty || words.allSatisfy(\.isNumber) { return host }
        return clip(words.prefix(1).uppercased() + words.dropFirst())
    }

    public static func displayHost(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The first line that has something on it, cut to fit a slip.
    public static func title(forText text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? text
        return clip(line)
    }

    public static func cleanTitle(_ raw: String) -> String? {
        // Control and format characters (bidi overrides among them) could make a page's title read
        // as something else on the card; they carry nothing worth keeping.
        let visible = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            let category = $0.properties.generalCategory
            return category != .control && category != .format
        }))
        let one = visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return one.isEmpty || isPlaceholderTitle(one) ? nil : clip(one)
    }

    /// What some sites call every page while a script sends you on: worse than the guess from the address.
    public static func isPlaceholderTitle(_ title: String) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .…"))
        return ["redirecting", "just a moment", "loading", "please wait", "untitled", "attention required! | cloudflare"].contains(t)
    }

    static func clip(_ s: String) -> String {
        s.count > titleLength ? String(s.prefix(titleLength - 1)) + "…" : s
    }

    /// A pasted picture has no name; the time it went in is the most useful one.
    static func imageTitle(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f.string(from: date)
    }
}
