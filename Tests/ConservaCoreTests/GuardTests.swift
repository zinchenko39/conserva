import Foundation
import Testing
@testable import ConservaCore

/// What comes from outside the app (a shelf.json edited by hand, a page's title, a pasted address)
/// is kept where it belongs.
struct GuardTests {
    private func tempHome() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("conserva-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aFileNameWithAPathInItPointsNowhere() {
        let store = ShelfStore(home: tempHome())
        let item = Item(kind: .file, title: "x", fileName: "../../shelf.json")
        #expect(store.fileURL(of: item) == nil)
        #expect(store.fileURL(of: Item(kind: .file, title: "x", fileName: "")) == nil)
        #expect(store.fileURL(of: Item(kind: .file, title: "x", fileName: "..")) == nil)
        #expect(store.fileURL(of: Item(kind: .file, title: "x", fileName: ".")) == nil)
        #expect(store.fileURL(of: Item(kind: .file, title: "x", fileName: "abc.pdf"))?.lastPathComponent == "abc.pdf")
    }

    @Test func anOriginalNameWithAPathInItStaysOneName() throws {
        let home = tempHome()
        let store = ShelfStore(home: home)
        let original = home.appendingPathComponent("doc.pdf")
        try Data([1]).write(to: original)
        var item = try store.store(Intake.drafts(from: [.fileURL(original)])[0])
        item.originalName = "../../../outside/doc.pdf"
        var trashed: [URL] = []
        store.moveToTrash = { trashed.append($0); try FileManager.default.removeItem(at: $0) }
        store.trashFile(of: item)
        #expect(trashed.map(\.lastPathComponent) == ["..-..-..-outside-doc.pdf"])
        #expect(trashed.allSatisfy { $0.standardizedFileURL.path.hasPrefix(home.standardizedFileURL.path) })
    }

    @Test func aShelfThatCannotBeReadThrowsInsteadOfVanishing() throws {
        let home = tempHome()
        let store = ShelfStore(home: home)
        try store.save(Shelf.starter(names: ["Links"]))
        let shelf = home.appendingPathComponent("shelf.json")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: shelf.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: shelf.path) }
        #expect(throws: (any Error).self) { try store.load() }
        // Still there, and not set aside: it was never decoded.
        #expect(FileManager.default.fileExists(atPath: shelf.path))
        #expect(!store.hasSetAsideShelf)
    }

    @Test func privateHostsAreToldFromPublicOnes() {
        for s in ["http://localhost:8080/x", "http://127.0.0.1/", "http://192.168.1.1/admin", "http://printer.local/", "http://[::1]/",
                  "http://127.1/", "http://0x7f.1/", "http://2130706433/", "http://router/", "http://nas.lan/",
                  "http://router.home.arpa/"] {
            #expect(Intake.isPrivateHost(URL(string: s)!), "\(s)")
        }
        for s in ["https://example.com", "https://10.example.org/x", "https://www.swift.org", "https://1.1.1.1.example.com/"] {
            #expect(!Intake.isPrivateHost(URL(string: s)!), "\(s)")
        }
    }

    @Test func aShelfFromANewerConservaIsRefusedAndLeftAlone() throws {
        let home = tempHome()
        let store = ShelfStore(home: home)
        let shelf = home.appendingPathComponent("shelf.json")
        try Data(#"{"version": \#(Shelf.currentVersion + 1), "jars": [], "somethingNew": true}"#.utf8).write(to: shelf)
        #expect(throws: ShelfStore.LoadError.self) { try store.load() }
        #expect(FileManager.default.fileExists(atPath: shelf.path))
        #expect(!store.hasSetAsideShelf)
    }

    @Test func emptyingAJarGoesThroughTheRules() {
        var shelf = Shelf.starter(names: ["Links"])
        let id = shelf.jars[0].id
        shelf.add([Item(kind: .text, title: "a"), Item(kind: .text, title: "b")], to: id)
        let gone = shelf.empty(id)
        #expect(gone.map(\.title) == ["a", "b"])
        #expect(shelf.jars[0].items.isEmpty)
        #expect(shelf.empty(UUID()).isEmpty)
    }

    @Test func aFolderIsClaimedByOneStoreAtATime() {
        let home = tempHome()
        let first = ShelfStore(home: home), second = ShelfStore(home: home)
        #expect(first.claim())
        #expect(first.claim(), "claiming again from the same store is fine")
        #expect(!second.claim(), "another store on the same folder is turned away")
        #expect(ShelfStore(home: tempHome()).claim(), "a different folder is free")
    }

    @Test func controlCharactersAreDroppedFromPageTitles() {
        #expect(Intake.cleanTitle("Safe \u{202E}txt.exe") == "Safe txt.exe")
        #expect(Intake.cleanTitle("A\u{0000}B\u{200B}C") == "ABC")
    }
}
