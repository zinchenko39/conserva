import Foundation
import Testing
@testable import ConservaCore

struct DustTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    func jar(itemsAddedDaysAgo ages: [Double], takenDaysAgo taken: Double? = nil) -> Jar {
        Jar(name: "Jar", items: ages.map { Item(kind: .text, title: "x", addedAt: daysAgo($0)) },
            lastTakenAt: taken.map(daysAgo))
    }

    @Test func cleanUntilTheFirstDustThenThickerUntilFull() {
        #expect(Dust.level(jar(itemsAddedDaysAgo: [6]), after: 7, now: now) == 0)
        #expect(Dust.level(jar(itemsAddedDaysAgo: [7]), after: 7, now: now) == 0)
        let halfway = Dust.level(jar(itemsAddedDaysAgo: [24.5]), after: 7, now: now)
        #expect(abs(halfway - 0.5) < 0.0001)
        #expect(Dust.level(jar(itemsAddedDaysAgo: [42]), after: 7, now: now) == 1)
        #expect(Dust.level(jar(itemsAddedDaysAgo: [400]), after: 7, now: now) == 1)
    }

    @Test func theOldestThingStillInTheJarCounts() {
        #expect(Dust.level(jar(itemsAddedDaysAgo: [1, 30]), after: 7, now: now) > 0)
    }

    @Test func takingSomethingOutStartsTheDustAgain() {
        #expect(Dust.level(jar(itemsAddedDaysAgo: [60], takenDaysAgo: 2), after: 7, now: now) == 0)
        var shelf = Shelf(jars: [jar(itemsAddedDaysAgo: [60])])
        shelf.markTaken(from: shelf.jars[0].id, at: now)
        #expect(Dust.level(shelf.jars[0], after: 7, now: now) == 0)
    }

    @Test func aNewThingInALongEmptyJarArrivesClean() {
        #expect(Dust.level(jar(itemsAddedDaysAgo: [0], takenDaysAgo: 90), after: 7, now: now) == 0)
    }

    @Test func emptyJarsAndNeverDoNotGatherDust() {
        #expect(Dust.since(jar(itemsAddedDaysAgo: [])) == nil)
        #expect(Dust.level(jar(itemsAddedDaysAgo: [], takenDaysAgo: 90), after: 7, now: now) == 0)
        #expect(Dust.level(jar(itemsAddedDaysAgo: [90]), after: 0, now: now) == 0)
    }

    @Test func theDaysSetTheTimescale() {
        let j = jar(itemsAddedDaysAgo: [10])
        #expect(Dust.level(j, after: 3, now: now) > Dust.level(j, after: 7, now: now))
        #expect(Dust.level(j, after: 14, now: now) == 0)
    }

    @Test func shelvesSavedBeforeLoadWithoutADate() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","items":[]}"#
        let jar = try JSONDecoder().decode(Jar.self, from: Data(old.utf8))
        #expect(jar.lastTakenAt == nil)
    }
}
