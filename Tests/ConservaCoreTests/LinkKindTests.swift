import Foundation
import Testing
@testable import ConservaCore

struct LinkKindTests {
    func kind(_ s: String) -> LinkKind { LinkKind.of(URL(string: s)!) }

    @Test func sitesAreSortedByWhatTheyHold() {
        #expect(kind("https://www.youtube.com/watch?v=abc") == .video)
        #expect(kind("https://youtu.be/abc") == .video)
        #expect(kind("https://www.linkedin.com/posts/anna_design-123") == .post)
        #expect(kind("https://t.me/channel/42") == .post)
        #expect(kind("https://habr.com/ru/articles/1/") == .article)
        #expect(kind("https://de.wikipedia.org/wiki/Glasgefäß".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) == .article)
        #expect(kind("https://github.com/apple/swift") == .code)
        #expect(kind("https://music.yandex.ru/album/1") == .audio)
        #expect(kind("https://www.ozon.ru/product/banka-1/") == .product)
        #expect(kind("https://docs.google.com/document/d/1") == .document)
        #expect(kind("https://www.kinopoisk.ru/film/42664/") == .page)
    }

    @Test func narrowRulesComeBeforeTheirSites() {
        #expect(kind("https://www.google.com/maps/place/x") == .place)
        #expect(kind("https://www.google.com/search?q=x") == .page)
        #expect(kind("https://yandex.ru/maps/-/abc") == .place)
        #expect(kind("https://music.youtube.com/watch?v=abc") == .audio)
        #expect(kind("https://vk.com/video-1_2") == .video)
        #expect(kind("https://vk.com/wall-1_2") == .post)
    }

    @Test func onlyTheDomainAndItsSubdomainsCount() {
        #expect(kind("https://notyoutube.com/x") == .page)
        #expect(kind("https://m.youtube.com/watch?v=abc") == .video)
    }

    @Test func aRepositoryIsItsOwnerAndName() {
        #expect(LinkKind.repository(URL(string: "https://github.com/apple/swift/pulls")!) == "apple/swift")
        #expect(LinkKind.repository(URL(string: "https://github.com/apple")!) == nil)
        #expect(LinkKind.repository(URL(string: "https://stackoverflow.com/questions/1")!) == nil)
    }

    @Test func onlyLinksHaveALinkKind() {
        #expect(Item(kind: .text, title: "x").linkKind == nil)
        #expect(Item(kind: .link, title: "x", url: "https://youtu.be/a").linkKind == .video)
    }

    @Test func previewsOfLinksNoLongerOnTheShelfAreDeleted() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = ShelfStore(home: home)
        let kept = Item(kind: .link, title: "a", url: "https://youtu.be/a")
        let gone = UUID()
        try store.savePreview(Data([1]), to: store.iconURL(of: kept.id))
        try store.savePreview(Data([1]), to: store.previewURL(of: kept.id))
        try store.savePreview(Data([1]), to: store.iconURL(of: gone))
        let removed = store.sweepPreviews(keeping: Shelf(jars: [Jar(name: "J", items: [kept])]))
        #expect(removed == 1)
        #expect(FileManager.default.fileExists(atPath: store.iconURL(of: kept.id).path))
        #expect(!FileManager.default.fileExists(atPath: store.iconURL(of: gone).path))
    }
}
