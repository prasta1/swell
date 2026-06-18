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
        let r = ConditionsService.parseTide(fixture("noaa_tide", "json"))
        XCTAssertEqual(r.ft!, 2.14, accuracy: 0.001)
        XCTAssertEqual(r.rising, true)   // 2.100 → 2.140
    }

    func testParseWindOffshoreForSantaCruz() throws {
        // SC faces ~S; wind FROM 290 (WNW) blows toward the sea → offshore.
        let r = ConditionsService.parseWind(fixture("nws_wind", "json"))
        XCTAssertEqual(r.mph!, 21.7, accuracy: 0.2)   // 9.7 m/s → ~21.7 mph
        XCTAssertEqual(r.offshore, true)
    }
}
