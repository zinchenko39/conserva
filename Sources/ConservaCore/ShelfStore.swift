import Foundation

/// The shelf on disk: `shelf.json` plus a `files` folder with a private copy of
/// every picture and file put into a jar, so moving or deleting the original
/// does not empty the jar. A stored file Conserva lets go of goes to the Trash, never straight
/// out of existence: deleting a thing, emptying a jar and tidying up after a failed save can all
/// be undone from there.
public final class ShelfStore {
    public let home: URL
    public var shelfURL: URL { home.appendingPathComponent("shelf.json") }
    public var filesURL: URL { home.appendingPathComponent("files", isDirectory: true) }
    /// A link's site icon and, for a video, its still: fetched with the page title, kept only as long as
    /// the link is, and fetched again rather than missed, so they never go to the Trash.
    public var previewsURL: URL { home.appendingPathComponent("previews", isDirectory: true) }
    /// Where a stored file is renamed before it goes to the Trash.
    private var leavingURL: URL { home.appendingPathComponent(".leaving", isDirectory: true) }

    /// Sends a file to the Trash, or to `AppPaths.trash` for a test instance. Tests swap it so they
    /// never touch the real one.
    public var moveToTrash: (URL) throws -> Void = { url in
        guard let stand = AppPaths.trash else { try FileManager.default.trashItem(at: url, resultingItemURL: nil); return }
        let folder = stand.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
    }

    public init(home: URL = AppPaths.home) {
        self.home = home
    }

    private var claimFile: Int32 = -1

    /// Takes the folder for this process: false if another one holds it. The claim is a lock on a
    /// file in the folder, which the system lets go of when the process ends, however it ends.
    public func claim() -> Bool {
        guard claimFile < 0 else { return true }
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let fd = open(home.appendingPathComponent(".claim").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return true }  // nowhere to lock: better one copy running than none
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        claimFile = fd
        return true
    }

    /// Nil when there is no shelf yet. A file that cannot be decoded is moved aside rather than
    /// overwritten, so a bad write never costs the user their jars. One that is there but cannot
    /// be read at all (permissions, a failing disk) throws: the caller must not save over it.
    public func load() throws -> Shelf? {
        guard FileManager.default.fileExists(atPath: shelfURL.path) else { return nil }
        let data = try Data(contentsOf: shelfURL)
        // A shelf written by a newer Conserva is left alone: this one would not know what it loses.
        if let header = try? Self.decoder.decode(Header.self, from: data), header.version > Shelf.currentVersion {
            throw LoadError.newerShelf(header.version)
        }
        do {
            return try Self.decoder.decode(Shelf.self, from: data)
        } catch {
            let aside = home.appendingPathComponent("shelf.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            // If it cannot even be moved aside, it must not be written over either.
            try FileManager.default.moveItem(at: shelfURL, to: aside)
            return nil
        }
    }

    private struct Header: Decodable { let version: Int }

    public enum LoadError: Error, LocalizedError {
        /// The shelf was saved by a newer version of Conserva than this one.
        case newerShelf(Int)

        public var errorDescription: String? {
            switch self {
            case .newerShelf(let version):
                return "The shelf was saved by a newer Conserva (format \(version); this one reads up to \(Shelf.currentVersion))."
            }
        }
    }

    public func save(_ shelf: Shelf) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Self.encoder.encode(shelf).write(to: shelfURL, options: .atomic)
    }

    /// Copies whatever the draft brings into the files folder and returns the item pointing at it.
    public func store(_ draft: Draft) throws -> Item {
        var item = draft.item
        switch draft.source {
        case .none:
            return item
        case .copy(let url):
            let name = Self.fileName(for: item.id, extension: url.pathExtension)
            try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: filesURL.appendingPathComponent(name))
            item.fileName = name
        case .data(let data, let ext):
            let name = Self.fileName(for: item.id, extension: ext)
            try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
            try data.write(to: filesURL.appendingPathComponent(name), options: .atomic)
            item.fileName = name
        }
        return item
    }

    public func iconURL(of id: UUID) -> URL { previewsURL.appendingPathComponent("\(id.uuidString).icon.png") }
    public func previewURL(of id: UUID) -> URL { previewsURL.appendingPathComponent("\(id.uuidString).preview.jpg") }

    public func savePreview(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: previewsURL, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Deletes icons and stills of links no longer on the shelf. Returns how many went.
    @discardableResult
    public func sweepPreviews(keeping shelf: Shelf) -> Int {
        let keep = Set(shelf.jars.flatMap { $0.items.map(\.id.uuidString) })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: previewsURL.path)) ?? []
        var removed = 0
        for name in names where !name.hasPrefix(".") {
            let id = String(name.prefix { $0 != "." })
            guard !keep.contains(id) else { continue }
            if (try? FileManager.default.removeItem(at: previewsURL.appendingPathComponent(name))) != nil { removed += 1 }
        }
        return removed
    }

    /// Only a plain name inside `files/`: a shelf.json edited by hand gets no further. `.` and `..` have no
    /// slash in them but are `files/` itself and the whole shelf folder, which removing the thing would trash.
    public func fileURL(of item: Item) -> URL? {
        guard let name = item.fileName, !name.isEmpty, name != ".", name != "..", name == Self.plainName(name) else { return nil }
        return filesURL.appendingPathComponent(name)
    }

    /// A single path component: slashes and colons become dashes, so a name from outside
    /// (the file's own, or an edited shelf.json) cannot point anywhere but where it is put.
    static func plainName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// Sends an item's stored file to the Trash under the name it came with, so it can be told
    /// apart there and put back. If there is no Trash to send it to, it is deleted: the user asked
    /// for it to go.
    public func trashFile(of item: Item) {
        guard let url = fileURL(of: item), FileManager.default.fileExists(atPath: url.path) else { return }
        let named = renamed(url, to: Self.plainName(item.originalName ?? fallbackName(item, url)))
        do { try moveToTrash(named) } catch { try? FileManager.default.removeItem(at: named) }
        // The emptied folder it was renamed in, if it was.
        let folder = named.deletingLastPathComponent()
        if folder.deletingLastPathComponent().standardizedFileURL == leavingURL.standardizedFileURL {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Sends stored files no item points to any more to the Trash: left behind if the app stopped
    /// between copying a file and saving the shelf, or if saving failed. While an unreadable shelf
    /// has been set aside nothing is touched, as its things still point to their files. A file
    /// the Trash will not take stays. Returns how many went.
    @discardableResult
    public func sweepOrphans(keeping shelf: Shelf) -> Int {
        guard !hasSetAsideShelf else { return 0 }
        let keep = shelf.referencedFiles
        let names = (try? FileManager.default.contentsOfDirectory(atPath: filesURL.path)) ?? []
        var moved = 0
        for name in names where !keep.contains(name) && !name.hasPrefix(".") {
            if (try? moveToTrash(filesURL.appendingPathComponent(name))) != nil { moved += 1 }
        }
        return moved
    }

    /// A `shelf.json` that could not be read has been moved aside and is still there.
    public var hasSetAsideShelf: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return names.contains { $0.hasPrefix("shelf.unreadable-") }
    }

    /// Moves the file into a folder of its own under a new name, ready for the Trash; where that
    /// cannot be done, the file as it is.
    private func renamed(_ url: URL, to name: String) -> URL {
        let folder = leavingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            return url
        }
    }

    /// A pasted picture has no name of its own: its title, with the stored file's extension.
    private func fallbackName(_ item: Item, _ url: URL) -> String {
        url.pathExtension.isEmpty ? item.title : "\(item.title).\(url.pathExtension)"
    }

    static func fileName(for id: UUID, extension ext: String) -> String {
        ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext.lowercased())"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
