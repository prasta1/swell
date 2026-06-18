import XCTest
import CoreGraphics
@testable import Swell

/// Tests the pure coordinate transform that maps Vision boxes (normalized,
/// bottom-left origin, relative to the water-region crop) into full-frame
/// normalized coordinates with a top-left origin for the overlay.
final class DetectionGeometryTests: XCTestCase {

    private let crop = CGRect(x: 100, y: 200, width: 400, height: 400)   // in a 1000×1000 frame

    func testFullBoxMapsToWholeCrop() {
        // A Vision box covering the entire crop maps to the crop's full extent.
        let box = CGRect(x: 0, y: 0, width: 1, height: 1)
        let mapped = YOLODetector.fullFrameBox(visionBox: box, cropRectPx: crop,
                                               imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(mapped.minX, 0.10, accuracy: 0.0001)
        XCTAssertEqual(mapped.minY, 0.20, accuracy: 0.0001)
        XCTAssertEqual(mapped.width, 0.40, accuracy: 0.0001)
        XCTAssertEqual(mapped.height, 0.40, accuracy: 0.0001)
    }

    func testBottomLeftVisionBoxMapsToLowerLeftOfCrop() {
        // Bottom-left quarter in Vision (origin bottom-left) → lower-left quarter
        // in top-left coords: crop spans y 0.2–0.6, so the lower half is 0.4–0.6.
        let box = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let mapped = YOLODetector.fullFrameBox(visionBox: box, cropRectPx: crop,
                                               imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(mapped.minX, 0.10, accuracy: 0.0001)
        XCTAssertEqual(mapped.minY, 0.40, accuracy: 0.0001)
        XCTAssertEqual(mapped.width, 0.20, accuracy: 0.0001)
        XCTAssertEqual(mapped.height, 0.20, accuracy: 0.0001)
    }

    func testTopRightVisionBoxMapsToUpperRightOfCrop() {
        // Top-right quarter in Vision → upper-right quarter in top-left coords.
        let box = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        let mapped = YOLODetector.fullFrameBox(visionBox: box, cropRectPx: crop,
                                               imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(mapped.minX, 0.30, accuracy: 0.0001)   // 100 + 0.5*400 = 300 → 0.3
        XCTAssertEqual(mapped.minY, 0.20, accuracy: 0.0001)   // top of crop
        XCTAssertEqual(mapped.width, 0.20, accuracy: 0.0001)
        XCTAssertEqual(mapped.height, 0.20, accuracy: 0.0001)
    }
}
