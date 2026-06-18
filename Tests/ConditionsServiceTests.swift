import XCTest
@testable import Swell

final class ConditionsServiceTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) -> Data {
        let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext)!
        return try! Data(contentsOf: url)
    }

    func testParseNDBCSwell() throws {
        let r = ConditionsService.parseNDBC(fixture("ndbc_46042", "txt"))
        XCTAssertEqual(r.heightFt!, 3.28, accuracy: 0.05)   // 1.0 m → 3.28 ft
        XCTAssertEqual(r.periodS!, 14.0, accuracy: 0.01)
    }

    func testParseTideRising() throws {
        // `now` past both rows → nearest is the last (2.140), rising vs 2.100.
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let r = ConditionsService.parseTide(fixture("noaa_tide", "json"), now: now)
        XCTAssertEqual(r.ft!, 2.14, accuracy: 0.001)
        XCTAssertEqual(r.rising, true)   // 2.100 → 2.140
    }

    func testParseTideFalling() {
        let json = #"{"predictions":[{"t":"2026-06-18 10:00","v":"4.000"},{"t":"2026-06-18 10:06","v":"3.800"}]}"#.data(using: .utf8)!
        let r = ConditionsService.parseTide(json, now: Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(r.ft!, 3.8, accuracy: 0.001)
        XCTAssertEqual(r.rising, false)   // 4.000 → 3.800
    }

    func testParseWindOffshoreForSantaCruz() throws {
        // SC faces ~S; wind FROM WNW (292.5°) blows toward the sea → offshore.
        let r = ConditionsService.parseWind(fixture("nws_wind", "json"))
        XCTAssertEqual(r.mph!, 10, accuracy: 0.01)   // "10 mph" string, already in mph
        XCTAssertEqual(r.offshore, true)
    }

    func testParseWindOnshoreFromSouth() {
        let json = #"{"properties":{"periods":[{"windSpeed":"8 mph","windDirection":"S"}]}}"#.data(using: .utf8)!
        let r = ConditionsService.parseWind(json)
        XCTAssertEqual(r.mph!, 8, accuracy: 0.01)
        XCTAssertEqual(r.offshore, false)   // 180° onshore
    }

    func testCompassToDegrees() {
        XCTAssertEqual(ConditionsService.compassToDegrees("N"), 0)
        XCTAssertEqual(ConditionsService.compassToDegrees("E"), 90)
        XCTAssertEqual(ConditionsService.compassToDegrees("WNW"), 292.5)
        XCTAssertNil(ConditionsService.compassToDegrees("bogus"))
    }
}
