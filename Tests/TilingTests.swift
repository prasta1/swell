import XCTest
import CoreGraphics
@testable import Swell

/// Tests the pure tiling + merge math behind the recall improvement: IoU,
/// non-max suppression, and tile-grid generation.
final class TilingTests: XCTestCase {

    // MARK: - IoU

    func testIoUIdentical() {
        let r = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(YOLODetector.iou(r, r), 1.0, accuracy: 0.0001)
    }

    func testIoUDisjoint() {
        XCTAssertEqual(YOLODetector.iou(CGRect(x: 0, y: 0, width: 10, height: 10),
                                        CGRect(x: 100, y: 100, width: 10, height: 10)), 0)
    }

    func testIoUHalfOverlap() {
        // Two 10×10 boxes sharing a 5×10 strip → inter 50, union 150 → 1/3.
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 5, y: 0, width: 10, height: 10)
        XCTAssertEqual(YOLODetector.iou(a, b), 1.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - Non-max suppression

    func testNMSDropsOverlappingLowerScore() {
        let a = YOLODetector.ScoredBox(rect: CGRect(x: 0, y: 0, width: 10, height: 10), score: 0.9)
        let b = YOLODetector.ScoredBox(rect: CGRect(x: 1, y: 1, width: 10, height: 10), score: 0.6)
        let kept = YOLODetector.nonMaxSuppress([a, b], iouThreshold: 0.45)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.score, 0.9)   // keeps the stronger box
    }

    func testNMSKeepsDisjointAndSortsByScore() {
        let a = YOLODetector.ScoredBox(rect: CGRect(x: 0, y: 0, width: 10, height: 10), score: 0.5)
        let b = YOLODetector.ScoredBox(rect: CGRect(x: 100, y: 100, width: 10, height: 10), score: 0.9)
        let kept = YOLODetector.nonMaxSuppress([a, b], iouThreshold: 0.45)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(kept.first?.score, 0.9)
    }

    // MARK: - Tile generation

    func testSmallRegionIsOneTile() {
        let tiles = YOLODetector.tiles(in: CGRect(x: 0, y: 0, width: 400, height: 300),
                                       maxTile: 640, overlap: 0.2,
                                       imageBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(tiles.count, 1)
    }

    func testWideRegionGridCount() {
        // 2000×700, maxTile 640 → cols ceil(2000/640)=4, rows ceil(700/640)=2 → 8.
        let tiles = YOLODetector.tiles(in: CGRect(x: 0, y: 0, width: 2000, height: 700),
                                       maxTile: 640, overlap: 0.2,
                                       imageBounds: CGRect(x: 0, y: 0, width: 2000, height: 2000))
        XCTAssertEqual(tiles.count, 8)
    }

    func testTilesAreClampedToImage() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let tiles = YOLODetector.tiles(in: bounds, maxTile: 640, overlap: 0.2, imageBounds: bounds)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.minX, -0.001)
            XCTAssertGreaterThanOrEqual(tile.minY, -0.001)
            XCTAssertLessThanOrEqual(tile.maxX, 1000.001)
            XCTAssertLessThanOrEqual(tile.maxY, 1000.001)
        }
    }

    func testAdjacentTilesOverlap() {
        // 1000×400 → cols 2, rows 1 → two tiles that overlap horizontally.
        let tiles = YOLODetector.tiles(in: CGRect(x: 0, y: 0, width: 1000, height: 400),
                                       maxTile: 640, overlap: 0.2,
                                       imageBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(tiles.count, 2)
        XCTAssertGreaterThan(tiles[0].maxX, tiles[1].minX)
    }
}
