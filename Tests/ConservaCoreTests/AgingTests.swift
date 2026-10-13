import Foundation
import Testing
@testable import ConservaCore

struct AgingTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!

    @Test func freshPaperIsWhite() {
        #expect(Aging.yellowing(since: now, now: now) == 0)
        #expect(Aging.days(since: now, now: now) == 0)
    }

    @Test func yellowingGrowsWithTheDaysAndStopsAtFull() {
        let halfway = now.addingTimeInterval(-Aging.fullAfterDays / 2 * 86_400)
        #expect(abs(Aging.yellowing(since: halfway, now: now) - 0.5) < 0.001)
        let long = now.addingTimeInterval(-400 * 86_400)
        #expect(Aging.yellowing(since: long, now: now) == 1)
        #expect(Aging.days(since: long, now: now) == 400)
    }

    @Test func aDateInTheFutureCountsAsToday() {
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(Aging.yellowing(since: tomorrow, now: now) == 0)
        #expect(Aging.days(since: tomorrow, now: now) == 0)
    }
}
