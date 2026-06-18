import XCTest
import GRDB
@testable import Swell

final class HistoryStoreTests: XCTestCase {
    func testAppendAndFetchLatest() throws {
        let store = try HistoryStore(inMemory: true)
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        try store.append(Sample(spotID: "cowells", timestamp: t, count: 4, confidence: 0.8))
        let latest = try store.latest(spotID: "cowells")
        XCTAssertEqual(latest?.count, 4)
        XCTAssertEqual(latest?.timestamp, t)
    }

    func testLatestReturnsNilWhenEmpty() throws {
        let store = try HistoryStore(inMemory: true)
        XCTAssertNil(try store.latest(spotID: "cowells"))
    }

    func testTypicalCountByWeekdayHour() throws {
        let store = try HistoryStore(inMemory: true)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Three Saturdays at 14:00 UTC with counts 4, 8, 12 → median 8
        let base = DateComponents(calendar: cal, year: 2026, month: 6, day: 6, hour: 14) // Sat
        for (i, c) in [4, 8, 12].enumerated() {
            let d = cal.date(byAdding: .day, value: i * 7, to: cal.date(from: base)!)!
            try store.append(Sample(spotID: "cowells", timestamp: d, count: c, confidence: 0.9))
        }
        let query = cal.date(from: DateComponents(calendar: cal, year: 2026, month: 7, day: 4, hour: 14))! // Sat
        XCTAssertEqual(try store.typicalCount(spotID: "cowells", for: query, calendar: cal), 8)
    }
}
