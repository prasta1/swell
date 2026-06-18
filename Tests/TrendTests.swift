import XCTest
@testable import Swell

final class TrendTests: XCTestCase {
    func testMedianOfCounts() {
        XCTAssertEqual(median([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(median([5]), 5)
        XCTAssertNil(median([]))
    }

    func testTrendClassification() {
        XCTAssertEqual(trend(current: 15, typical: 10), .busy)
        XCTAssertEqual(trend(current: 5, typical: 10), .quiet)
        XCTAssertEqual(trend(current: 10, typical: 10), .typical)
        XCTAssertEqual(trend(current: 7, typical: nil), .unknown)
    }
}
