import XCTest
@testable import Swell

final class SpotRegistryTests: XCTestCase {
    private func fixtureURL() -> URL {
        Bundle(for: type(of: self)).url(forResource: "spots.fixture", withExtension: "json")!
    }

    func testLoadsAllSpots() throws {
        let registry = try SpotRegistry(url: fixtureURL())
        XCTAssertEqual(registry.spots.count, 3)
        XCTAssertEqual(registry.spots[0].id, "cowells")
    }

    func testActiveSpotsExcludeLocked() throws {
        let registry = try SpotRegistry(url: fixtureURL())
        XCTAssertEqual(registry.activeSpots.map(\.id), ["cowells", "seacliff"])
    }
}
