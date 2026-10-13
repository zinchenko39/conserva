import Foundation
import Testing
@testable import ConservaCore

struct IntakeTests {
    @Test func oneLinkBecomesALink() {
        let d = Intake.drafts(from: [.text("https://github.com/swiftlang/swift")])
        #expect(d.count == 1)
        #expect(d[0].item.kind == .link)
        #expect(d[0].item.url == "https://github.com/swiftlang/swift")
        #expect(d[0].item.title == "Swift")
    }

    @Test func severalLinksOnSeparateLinesBecomeSeveralLinks() {
        let d = Intake.drafts(from: [.text("https://a.example/one\n  https://b.example/two-words\n")])
        #expect(d.map(\.item.kind) == [.link, .link])
        #expect(d[1].item.title == "Two words")
    }

    @Test func textAroundALinkIsANote() {
        let d = Intake.drafts(from: [.text("Read this later: https://example.com/x")])
        #expect(d.count == 1)
        #expect(d[0].item.kind == .text)
        #expect(d[0].item.text == "Read this later: https://example.com/x")
    }

    @Test func bareWwwAddressIsALink() {
        let d = Intake.drafts(from: [.text("www.swift.org")])
        #expect(d.first?.item.kind == .link)
        #expect(d.first?.item.url == "https://www.swift.org")
        #expect(d.first?.item.title == "swift.org")
    }

    @Test func notALinkWithoutADotInTheHost() {
        #expect(Intake.webURL("https://localhost") == nil)
        #expect(Intake.webURL("ftp://example.com") == nil)
        #expect(Intake.webURL("The Master and Margarita") == nil)
    }

    @Test func bookTitleIsANoteTitledByItsFirstLine() {
        let d = Intake.drafts(from: [.text("\n  Le Guin. The Left Hand of Darkness\nRecommended by Zoë")])
        #expect(d[0].item.kind == .text)
        #expect(d[0].item.title == "Le Guin. The Left Hand of Darkness")
    }

    @Test func longTitlesAreClipped() {
        let long = String(repeating: "é", count: 200)
        let t = Intake.title(forText: long)
        #expect(t.count == Intake.titleLength)
        #expect(t.hasSuffix("…"))
    }

    @Test func blankTextIsIgnored() {
        #expect(Intake.drafts(from: [.text("  \n\t ")]).isEmpty)
    }

    @Test func theSameLinkTwiceInOneDropIsKeptOnce() {
        let u = URL(string: "https://example.com/page")!
        let d = Intake.drafts(from: [.webURL(u, title: "Page"), .text("https://example.com/page")])
        #expect(d.count == 1)
        #expect(d[0].item.title == "Page")
    }

    @Test func aBrowserTabKeepsItsTitle() {
        let u = URL(string: "https://en.wikipedia.org/wiki/Hourglass")!
        let d = Intake.drafts(from: [.webURL(u, title: "  Hourglass -   Wikipedia ")])
        #expect(d[0].item.title == "Hourglass - Wikipedia")
    }

    @Test func titleFromURLDropsTheExtensionAndNumbersOnlyPaths() {
        #expect(Intake.title(forURL: URL(string: "https://example.com/docs/getting_started.html")!) == "Getting started")
        #expect(Intake.title(forURL: URL(string: "https://news.ycombinator.com/item/4123")!) == "news.ycombinator.com")
        #expect(Intake.title(forURL: URL(string: "https://www.example.com/")!) == "example.com")
    }

    @Test func picturesAndOtherFilesAreToldApartByExtension() {
        let d = Intake.drafts(from: [.fileURL(URL(fileURLWithPath: "/tmp/Screen Shot.PNG")),
                                     .fileURL(URL(fileURLWithPath: "/tmp/Beck — Extreme Programming Explained.pdf"))])
        #expect(d.map(\.item.kind) == [.image, .file])
        #expect(d[0].item.title == "Screen Shot")
        #expect(d[1].item.title == "Beck — Extreme Programming Explained.pdf")
        #expect(d[0].source == .copy(URL(fileURLWithPath: "/tmp/Screen Shot.PNG")))
    }

    @Test func pastedPictureIsNamedByTime() {
        let date = ISO8601DateFormatter().date(from: "2026-10-09T12:34:00Z")!
        let d = Intake.drafts(from: [.imageData(Data([1, 2, 3]), fileExtension: "png")], now: date)
        #expect(d[0].item.kind == .image)
        #expect(d[0].item.byteSize == 3)
        #expect(d[0].item.title.hasPrefix("2026-10-"))
    }

    @Test func placeholderPageTitlesAreIgnored() {
        #expect(Intake.cleanTitle("Redirecting…") == nil)
        #expect(Intake.cleanTitle("Just a moment...") == nil)
        #expect(Intake.cleanTitle("Redirecting to the docs") == "Redirecting to the docs")
    }
}
