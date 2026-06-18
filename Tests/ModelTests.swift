import XCTest
@testable import Swell

final class ModelTests: XCTestCase {
    func testWaterRegionDecodesNormalizedPolygon() throws {
        let json = """
        {"points": [[0.1, 0.2], [0.9, 0.2], [0.9, 0.8], [0.1, 0.8]]}
        """.data(using: .utf8)!
        let region = try JSONDecoder().decode(WaterRegion.self, from: json)
        XCTAssertEqual(region.points.count, 4)
        XCTAssertEqual(region.points[2].x, 0.9, accuracy: 0.0001)
        XCTAssertEqual(region.points[2].y, 0.8, accuracy: 0.0001)
    }

    func testSourceDescriptorDecodesSnapshotAndHLS() throws {
        let json = """
        [{"kind":"snapshot","url":"https://e/c2.jpg"},
         {"kind":"hls","url":"https://e/p.m3u8"}]
        """.data(using: .utf8)!
        let sources = try JSONDecoder().decode([SourceDescriptor].self, from: json)
        XCTAssertEqual(sources[0].kind, .snapshot)
        XCTAssertEqual(sources[1].kind, .hls)
    }
}
