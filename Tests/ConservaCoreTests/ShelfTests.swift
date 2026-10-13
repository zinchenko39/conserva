import Foundation
import Testing
@testable import ConservaCore

struct ShelfTests {
    @Test func jarsStopAtTheLimit() {
        var s = Shelf()
        for i in 0..<Shelf.maxJars {
            let added = s.addJar(named: "Jar \(i)")
            #expect(added != nil)
        }
        let extra = s.addJar(named: "One more")
        #expect(extra == nil)
        #expect(s.jars.count == Shelf.maxJars)
    }

    @Test func namesAreTidiedAndBlankNamesRefused() {
        var s = Shelf()
        let jar = s.addJar(named: "  Books   for\tlater ")!
        #expect(jar.name == "Books for later")
        let blank = s.addJar(named: "   ")
        #expect(blank == nil)
        let renamedToBlank = s.rename(jar.id, to: "\n")
        #expect(!renamedToBlank)
        let renamed = s.rename(jar.id, to: String(repeating: "x", count: 40))
        #expect(renamed)
        #expect(s.jars[0].name.count == Shelf.maxNameLength)
    }

    @Test func addLocateAndRemove() {
        var s = Shelf()
        let a = s.addJar(named: "A")!, b = s.addJar(named: "B")!
        let item = Item(kind: .link, title: "x", url: "https://x.example")
        s.add([item], to: b.id)
        #expect(s.locate(item.id)! == (jar: 1, item: 0))
        #expect(s.contains(link: "https://x.example", in: b.id))
        #expect(!s.contains(link: "https://x.example", in: a.id))
        let removed = s.remove(item.id)
        #expect(removed == item)
        #expect(s.locate(item.id) == nil)
    }

    @Test func agingGoesFromFreshToFullyYellow() {
        let now = Date()
        #expect(Aging.yellowing(since: now, now: now) == 0)
        #expect(abs(Aging.yellowing(since: now.addingTimeInterval(-15 * 86_400), now: now) - 0.5) < 0.001)
        #expect(Aging.yellowing(since: now.addingTimeInterval(-90 * 86_400), now: now) == 1)
        #expect(Aging.days(since: now.addingTimeInterval(-3.5 * 86_400), now: now) == 3)
        #expect(Aging.days(since: now.addingTimeInterval(3600), now: now) == 0)
    }
}

struct PlaceTests {
    @Test func placesAreKeptOnTheScreen() {
        #expect(Place(x: -0.2, y: 1.7) == Place(x: 0, y: 1))
    }

    @Test func placingTwiceAtTheSameSpotChangesNothing() {
        var s = Shelf.starter(names: ["A"])
        let id = s.jars[0].id
        let first = s.place(id, at: Place(x: 0.5, y: 0.25))
        let again = s.place(id, at: Place(x: 0.5, y: 0.25))
        #expect(first)
        #expect(!again)
        #expect(s.jars[0].place == Place(x: 0.5, y: 0.25))
    }

    @Test func aShelfSavedBeforePlacesExistedStillLoads() throws {
        let json = #"{"version":1,"jars":[{"id":"6E4C5B1A-1C55-4B53-9D0B-6B9F7E9E1A11","name":"Old","items":[]}]}"#
        let shelf = try JSONDecoder().decode(Shelf.self, from: Data(json.utf8))
        #expect(shelf.jars[0].name == "Old")
        #expect(shelf.jars[0].place == nil)
    }
}

struct ShelfStoreTests {
    private func tempHome() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("conserva-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func savesAndLoadsTheShelf() throws {
        let store = ShelfStore(home: tempHome())
        #expect(try store.load() == nil)
        var shelf = Shelf.starter(names: ["Links", "Books"])
        shelf.add([Item(kind: .text, title: "Note", text: "Note")], to: shelf.jars[1].id)
        try store.save(shelf)
        let loaded = try store.load()
        #expect(loaded?.jars.map(\.name) == ["Links", "Books"])
        #expect(loaded?.jars[1].items.first?.text == "Note")
    }

    @Test func anUnreadableFileIsMovedAsideNotLost() throws {
        let home = tempHome()
        let store = ShelfStore(home: home)
        try Data("{ not json".utf8).write(to: store.shelfURL)
        #expect(try store.load() == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: home.path)
        #expect(names.contains { $0.hasPrefix("shelf.unreadable-") })
        #expect(!FileManager.default.fileExists(atPath: store.shelfURL.path))
    }

    @Test func storesACopySoTheOriginalCanGo() throws {
        let home = tempHome()
        let store = ShelfStore(home: home)
        let original = home.appendingPathComponent("photo.jpg")
        try Data([9, 9, 9]).write(to: original)
        let draft = Intake.drafts(from: [.fileURL(original)])[0]
        let item = try store.store(draft)
        try FileManager.default.removeItem(at: original)
        let copy = try #require(store.fileURL(of: item))
        #expect(try Data(contentsOf: copy) == Data([9, 9, 9]))
        #expect(copy.lastPathComponent == "\(item.id.uuidString).jpg")
        var trashed: [String] = []
        store.moveToTrash = { trashed.append($0.lastPathComponent); try FileManager.default.removeItem(at: $0) }
        store.trashFile(of: item)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        // It goes to the Trash under the name it came with, so it can be found there.
        #expect(trashed == ["photo.jpg"])
    }

    @Test func pastedDataIsWrittenAsAFile() throws {
        let store = ShelfStore(home: tempHome())
        let item = try store.store(Intake.drafts(from: [.imageData(Data([1, 2]), fileExtension: "PNG")])[0])
        #expect(item.fileName?.hasSuffix(".png") == true)
        #expect(try Data(contentsOf: store.fileURL(of: item)!) == Data([1, 2]))
    }

    @Test func sweepTrashesOnlyFilesNothingPointsTo() throws {
        let store = ShelfStore(home: tempHome())
        var trashed: [String] = []
        store.moveToTrash = { trashed.append($0.lastPathComponent); try FileManager.default.removeItem(at: $0) }
        let kept = try store.store(Intake.drafts(from: [.imageData(Data([1]), fileExtension: "png")])[0])
        let stray = try store.store(Intake.drafts(from: [.imageData(Data([2]), fileExtension: "png")])[0])
        var shelf = Shelf.starter(names: ["A"])
        shelf.add([kept], to: shelf.jars[0].id)
        #expect(store.sweepOrphans(keeping: shelf) == 1)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(of: kept)!.path))
        #expect(trashed == [stray.fileName])
    }

    @Test func nothingIsSweptWhileAnUnreadableShelfIsSetAside() throws {
        let store = ShelfStore(home: tempHome())
        store.moveToTrash = { _ in Issue.record("nothing should go to the Trash") }
        let item = try store.store(Intake.drafts(from: [.imageData(Data([1]), fileExtension: "png")])[0])
        try Data("{ not json".utf8).write(to: store.shelfURL)
        #expect(try store.load() == nil)
        // A fresh shelf, as the app starts with after setting the old one aside: its things are not in it.
        #expect(store.sweepOrphans(keeping: Shelf.starter(names: ["A"])) == 0)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(of: item)!.path))
    }

    @Test func aFileTheTrashWillNotTakeStays() throws {
        let store = ShelfStore(home: tempHome())
        struct NoTrash: Error {}
        store.moveToTrash = { _ in throw NoTrash() }
        let stray = try store.store(Intake.drafts(from: [.imageData(Data([2]), fileExtension: "png")])[0])
        #expect(store.sweepOrphans(keeping: Shelf.starter(names: ["A"])) == 0)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(of: stray)!.path))
    }
}
