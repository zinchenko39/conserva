import AppKit
import ConservaCore
import LinkPresentation

/// The shelf the app shows, and the only place that changes it. Every change
/// is saved at once; the scene is told what changed through the callbacks.
@MainActor
final class ShelfModel {
    private(set) var shelf: Shelf
    let store: ShelfStore

    var onItemsAdded: ((_ jarID: UUID, _ items: [Item], _ from: CGPoint?) -> Void)?
    var onItemChanged: ((Item) -> Void)?
    var onJarsChanged: (() -> Void)?
    /// Saving failed, after it last worked: what was just put in may not be there next time.
    var onSaveFailed: ((Error) -> Void)?
    private var saveFailing = false
    /// The shelf on disk is there but could not be read. Nothing is saved over it: the jars shown
    /// are a stand-in for this run only.
    private(set) var loadError: Error?

    /// Page titles are fetched from the sites themselves. This is the only
    /// network access Conserva makes, and it can be turned off from the menu.
    var fetchesTitles: Bool {
        get { UserDefaults.standard.object(forKey: "fetchesTitles") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fetchesTitles") }
    }

    /// Days until a jar nothing has been taken out of starts to gather dust; 0 for never.
    var dustAfterDays: Int {
        get { UserDefaults.standard.object(forKey: "dustAfterDays") as? Int ?? Dust.defaultDays }
        set { UserDefaults.standard.set(newValue, forKey: "dustAfterDays") }
    }

    init(store: ShelfStore = ShelfStore()) {
        self.store = store
        var loaded: Shelf?
        do { loaded = try store.load() } catch { loadError = error }
        if let loaded {
            shelf = loaded
            store.sweepOrphans(keeping: loaded)
            store.sweepPreviews(keeping: loaded)
        } else {
            var starter = Shelf.starter(names: [L("starter.links"), L("starter.books"), L("starter.screenshots")])
            starter.add([Item(kind: .text, title: L("welcome.title"), text: L("welcome.text"))], to: starter.jars[0].id)
            shelf = starter
            save()
        }
    }

    func save() {
        // A shelf that could not be read is still the user's: it is never replaced by the stand-in.
        guard loadError == nil else { return }
        do {
            try store.save(shelf)
            saveFailing = false
        } catch {
            NSLog("Conserva: could not save the shelf: \(error)")
            // Said once, not at every move of a jar, until a save goes through again.
            if !saveFailing {
                saveFailing = true
                onSaveFailed?(error)
            }
        }
    }

    func jar(_ id: UUID) -> Jar? { shelf.jarIndex(id).map { shelf.jars[$0] } }

    func item(_ id: UUID) -> Item? { shelf.locate(id).map { shelf.jars[$0.jar].items[$0.item] } }

    func jarID(holding itemID: UUID) -> UUID? { shelf.locate(itemID).map { shelf.jars[$0.jar].id } }

    /// Stores what came in and puts it in the jar. Returns how many things went in;
    /// a link the jar already holds is skipped.
    @discardableResult
    func add(_ incoming: [Incoming], to jarID: UUID, from point: CGPoint? = nil) -> Int {
        var added: [Item] = []
        for draft in Intake.drafts(from: incoming) {
            if draft.item.kind == .link, let url = draft.item.url, shelf.contains(link: url, in: jarID) { continue }
            do { added.append(try store.store(draft)) } catch { NSLog("Conserva: could not store \(draft.item.title): \(error)") }
        }
        guard !added.isEmpty else { return 0 }
        shelf.add(added, to: jarID)
        save()
        onItemsAdded?(jarID, added, point)
        for item in added where item.kind == .link { fetchTitle(for: item) }
        return added.count
    }

    /// Something was taken out of the jar: its dust starts again.
    func markTaken(from jarID: UUID) {
        shelf.markTaken(from: jarID)
        save()
    }

    /// Takes the item out for good; its stored file goes to the Trash.
    func discard(_ itemID: UUID) {
        guard let item = shelf.remove(itemID) else { return }
        store.trashFile(of: item)
        save()
    }

    @discardableResult
    func addJar(named name: String) -> Jar? {
        guard let jar = shelf.addJar(named: name) else { return nil }
        save()
        onJarsChanged?()
        return jar
    }

    /// Remembers where a jar was left on the screen. Not announced: the scene put it there.
    func setPlace(_ jarID: UUID, _ place: Place) {
        if shelf.place(jarID, at: place) { save() }
    }

    func rename(_ jarID: UUID, to name: String) {
        guard shelf.rename(jarID, to: name) else { return }
        save()
        onJarsChanged?()
    }

    func removeJar(_ jarID: UUID) {
        guard let jar = shelf.removeJar(jarID) else { return }
        jar.items.forEach(store.trashFile)
        save()
        onJarsChanged?()
    }

    func emptyJar(_ jarID: UUID) {
        let gone = shelf.empty(jarID)
        guard !gone.isEmpty else { return }
        gone.forEach(store.trashFile)
        save()
        onJarsChanged?()
    }

    func fileURL(of item: Item) -> URL? { store.fileURL(of: item) }

    // MARK: Opening and copying

    /// A link's address as something safe to hand to the system: only web addresses are kept,
    /// so an edited shelf.json cannot make Open launch another scheme.
    static func webURL(of item: Item) -> URL? {
        guard let s = item.url, let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    func open(_ item: Item) {
        switch item.kind {
        case .link: if let url = Self.webURL(of: item) { NSWorkspace.shared.open(url) }
        case .image, .file: if let url = fileURL(of: item) { NSWorkspace.shared.open(url) }
        case .text: break
        }
    }

    func revealInFinder(_ item: Item) {
        if let url = fileURL(of: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func copy(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .link:
            if let s = item.url, let url = URL(string: s) { pb.writeObjects([url as NSURL]); pb.setString(s, forType: .string) }
        case .text:
            pb.setString(item.text ?? item.title, forType: .string)
        case .image:
            if let url = fileURL(of: item), let image = NSImage(contentsOf: url) { pb.writeObjects([image, url as NSURL]) }
        case .file:
            if let url = fileURL(of: item) { pb.writeObjects([url as NSURL]) }
        }
    }

    // MARK: Page titles

    /// The page's title, the site's icon and, for a video, its still all come back in the one answer.
    private func fetchTitle(for item: Item) {
        guard fetchesTitles, let url = Self.webURL(of: item), !Intake.isPrivateHost(url) else { return }
        let id = item.id
        let iconURL = store.iconURL(of: id), stillURL = store.previewURL(of: id)
        let wantsStill = item.linkKind == .video
        let provider = LPMetadataProvider()
        provider.timeout = 10
        provider.startFetchingMetadata(for: url) { metadata, _ in
            if let icon = metadata?.iconProvider {
                Self.loadImage(icon, longestSide: 64, jpeg: false) { [weak self] data in self?.keep(data, at: iconURL, for: id) }
            }
            if wantsStill, let still = metadata?.imageProvider {
                Self.loadImage(still, longestSide: 360, jpeg: true) { [weak self] data in self?.keep(data, at: stillURL, for: id) }
            }
            let title = metadata?.title
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let title, let clean = Intake.cleanTitle(title) else { return }
                    self.shelf.update(id) { $0.title = clean }
                    self.save()
                    if let updated = self.item(id) { self.onItemChanged?(updated) }
                }
            }
            // Named here so the provider lives until its own answer arrives; nothing else holds it.
            _ = provider
        }
    }

    private func keep(_ data: Data?, at url: URL, for id: UUID) {
        guard let data, item(id) != nil else { return }
        do { try store.savePreview(data, to: url) } catch { NSLog("Conserva: could not keep a link's picture: \(error)"); return }
        if let updated = item(id) { onItemChanged?(updated) }
    }

    /// Loads a picture a page offers and shrinks it to what a thing in a jar needs, off the main thread;
    /// hands back the encoded file on the main thread.
    nonisolated private static func loadImage(_ provider: NSItemProvider, longestSide: CGFloat, jpeg: Bool,
                                              done: @escaping @MainActor (Data?) -> Void) {
        provider.loadObject(ofClass: NSImage.self) { object, _ in
            let data = (object as? NSImage).flatMap { encode($0, longestSide: longestSide, jpeg: jpeg) }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(data) } }
        }
    }

    nonisolated private static func encode(_ image: NSImage, longestSide: CGFloat, jpeg: Bool) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, longestSide / CGFloat(max(source.width, source.height)))
        let w = max(1, Int(CGFloat(source.width) * scale)), h = max(1, Int(CGFloat(source.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: small).representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.8] : [:])
    }
}

/// Reads whatever was dropped or copied into things a jar can take.
enum Pasteboard {
    static let readTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff,
                                                           NSPasteboard.PasteboardType("public.jpeg"),
                                                           NSPasteboard.PasteboardType("public.heic")]

    static func incoming(from pb: NSPasteboard) -> [Incoming] {
        // Files first: a file dragged from Finder also carries its path as text.
        if let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            return files.map { .fileURL($0) }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let web = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            if !web.isEmpty {
                // Safari and Chrome put the page title next to a dragged link.
                let title = pb.string(forType: NSPasteboard.PasteboardType("public.url-name"))
                return web.map { .webURL($0, title: web.count == 1 ? title : nil) }
            }
        }
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.text(s)]
        }
        for (type, ext) in [(NSPasteboard.PasteboardType.png, "png"), (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
                            (NSPasteboard.PasteboardType("public.heic"), "heic")] {
            if let data = pb.data(forType: type) { return [.imageData(data, fileExtension: ext)] }
        }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return [.imageData(png, fileExtension: "png")]
        }
        return []
    }

    static func canRead(_ pb: NSPasteboard) -> Bool {
        pb.availableType(from: readTypes) != nil
    }

    /// Whether the clipboard holds a web address, found out without reading it: newer systems
    /// detect the pattern for us, which counts as no paste; older ones can only be asked whether an
    /// address type is on offer, so a bare address copied as text goes unnoticed there.
    @MainActor static func holdsLink(_ pb: NSPasteboard, _ done: @escaping @MainActor (Bool) -> Void) {
        if #available(macOS 15.4, *) {
            Task { @MainActor in
                let found = (try? await pb.detectedPatterns(for: [\.probableWebURL]))?.contains(\.probableWebURL) ?? false
                done(found)
            }
        } else {
            done(pb.availableType(from: [.URL]) != nil)
        }
    }
}
