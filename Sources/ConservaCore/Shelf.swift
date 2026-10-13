import Foundation

/// What a jar can hold. The kind decides how the thing is drawn and what
/// "open" and "copy" mean for it.
public enum ItemKind: String, Codable, Sendable {
    /// A web address.
    case link
    /// Any text that is not a link: a quote, a book title, a note to self.
    case text
    /// A picture, stored as a file in the shelf's folder.
    case image
    /// Any other file, stored as a copy in the shelf's folder.
    case file
}

public struct Item: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    /// What the slip says. For a link it starts as a guess from the address
    /// and is replaced by the page title once it is known.
    public var title: String
    /// The address, for a link.
    public var url: String?
    /// The full text, for a text item.
    public var text: String?
    /// The stored copy, relative to the shelf's files folder, for an image or a file.
    public var fileName: String?
    /// The name the file had when it was dropped, shown on the card.
    public var originalName: String?
    public var byteSize: Int?
    public var addedAt: Date

    public init(id: UUID = UUID(), kind: ItemKind, title: String, url: String? = nil, text: String? = nil,
                fileName: String? = nil, originalName: String? = nil, byteSize: Int? = nil, addedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.text = text
        self.fileName = fileName
        self.originalName = originalName
        self.byteSize = byteSize
        self.addedAt = addedAt
    }
}

public struct Jar: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Oldest first: the order things went in, so they settle in that order on launch.
    public internal(set) var items: [Item]
    /// Where the jar was left on the screen. Nil until it is first moved: it then stands in the default row.
    public var place: Place?
    /// The last time something was taken out of it. Nil until the first time; shelves saved before
    /// this was kept load as nil.
    public var lastTakenAt: Date?

    public init(id: UUID = UUID(), name: String, items: [Item] = [], place: Place? = nil, lastTakenAt: Date? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.place = place
        self.lastTakenAt = lastTakenAt
    }
}

/// A spot on the screen as fractions of its usable area, 0…1 from the bottom
/// left, so a jar stays in the same part of the screen when the screen changes.
public struct Place: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }
}

/// Everything Conserva keeps: the jars in shelf order, left to right.
public struct Shelf: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// More jars do not fit along the edge of a laptop screen at a size you can still read.
    public static let maxJars = 5
    /// The longest name that still fits on a jar's label.
    public static let maxNameLength = 24

    /// Changed only through the editing rules in `ShelfEditing`, so every rule the tests cover is
    /// the only way the shelf changes.
    public internal(set) var version: Int
    public internal(set) var jars: [Jar]

    public init(jars: [Jar] = []) {
        self.version = Self.currentVersion
        self.jars = jars
    }

    /// What a first launch starts with, so the shelf is not an empty puzzle.
    public static func starter(names: [String]) -> Shelf {
        Shelf(jars: names.map { Jar(name: $0) })
    }

    public func jarIndex(_ id: UUID) -> Int? { jars.firstIndex { $0.id == id } }

    /// The jar holding the item, and the item's position in it.
    public func locate(_ itemID: UUID) -> (jar: Int, item: Int)? {
        for (j, jar) in jars.enumerated() {
            if let i = jar.items.firstIndex(where: { $0.id == itemID }) { return (j, i) }
        }
        return nil
    }

    public static func cleanName(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxNameLength))
    }
}
