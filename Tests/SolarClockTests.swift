import XCTest
@testable import Swell

final class SolarClockTests: XCTestCase {
    func testDaylightGateUsesConfiguredWindow() {
        let clock = SolarClock(startHour: 6, endHour: 20)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let noon = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!
        let predawn = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 2))!
        XCTAssertTrue(clock.isDaylight(noon, calendar: cal))
        XCTAssertFalse(clock.isDaylight(predawn, calendar: cal))
    }
}
