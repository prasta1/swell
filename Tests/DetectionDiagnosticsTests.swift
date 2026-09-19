import Testing
import Foundation
import CoreGraphics
@testable import Swell

@Suite("Detection diagnostics", .timeLimit(.minutes(2)))
struct DetectionDiagnosticsTests {

    @Test("List all detections with confidence scores")
    func listAllDetections() async throws {
        let registry = try SpotRegistry.bundled()
        guard let spot = registry.spots.first(where: { $0.id == "cowells" }) else {
            Issue.record("Cowells spot not found in registry")
            return
        }

        let source = SnapshotSource(url: URL(string: spot.source.url)!)
        let frame = try await source.currentFrame()
        let detector = try YOLODetector()

        // Get detection with boxes
        let detection = try detector.count(in: frame.image, region: spot.waterRegion)

        print("\n📊 Frame: \(frame.image.width)x\(frame.image.height)")
        print("📍 Water region: \(spot.waterRegion.points)")
        print("🏄 Detected: \(detection.count ?? 0) surfers (confidence: \(String(format: "%.3f", detection.confidence)))")
        print("📦 Boxes: \(detection.boxes.count)")

        for (i, box) in detection.boxes.enumerated() {
            print("   Box \(i): x=\(String(format: "%.3f", box.minX)), y=\(String(format: "%.3f", box.minY)), w=\(String(format: "%.3f", box.width)), h=\(String(format: "%.3f", box.height))")
        }

        #expect(frame.image.width > 0)
    }

    @Test("Test detection at different confidence thresholds")
    func testConfidenceThresholds() async throws {
        let registry = try SpotRegistry.bundled()
        guard let spot = registry.spots.first(where: { $0.id == "cowells" }) else {
            Issue.record("Cowells spot not found")
            return
        }

        let source = SnapshotSource(url: URL(string: spot.source.url)!)
        let frame = try await source.currentFrame()
        let detector = try YOLODetector()

        print("\n🔬 Sweeping confidence thresholds (default: \(YOLODetector.minConfidence))")
        var counts: [Int] = []
        for threshold in stride(from: Float(0.05), through: 0.5, by: 0.05) {
            let detection = try detector.count(in: frame.image, region: spot.waterRegion,
                                               minConfidence: threshold)
            counts.append(detection.count ?? 0)
            print("   \(String(format: "%.2f", threshold)): \(detection.count ?? 0) surfers")
        }

        // Raising the cutoff can only ever drop detections, never add them.
        #expect(counts == counts.sorted(by: >))
    }
}
