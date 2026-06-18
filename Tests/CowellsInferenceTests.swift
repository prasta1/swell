import Testing
import Foundation
import CoreGraphics
@testable import Swell

@Suite("Cowells end-to-end inference", .timeLimit(.minutes(2)))
struct CowellsInferenceTests {

    @Test("Full pipeline: Cowells spot → frame → detector → detection → sample")
    func cowellsFullPipeline() async throws {
        // 1. Load registry and get Cowells spot
        let registry = try SpotRegistry.bundled()
        guard let spot = registry.spots.first(where: { $0.id == "cowells" }) else {
            Issue.record("Cowells spot not found in registry")
            return
        }
        print("✅ Spot loaded: \(spot.name) (\(spot.source.kind))")
        print("   Water region: \(spot.waterRegion.points)")

        // 2. Create frame source
        let source = SnapshotSource(url: URL(string: spot.source.url)!)
        print("✅ Frame source created")

        // 3. Fetch frame
        let frame = try await source.currentFrame()
        print("✅ Frame fetched: \(frame.image.width)x\(frame.image.height) @ \(frame.timestamp)")

        // 4. Create detector
        let detector = try YOLODetector()
        print("✅ YOLODetector loaded")

        // 5. Run detection
        let detection = try detector.count(in: frame.image, region: spot.waterRegion)
        print("✅ Detection: count=\(detection.count ?? -1), confidence=\(String(format: "%.3f", detection.confidence))")

        // 6. Create sample
        let sample = Sample(
            spotID: spot.id,
            timestamp: frame.timestamp,
            count: detection.count,
            confidence: detection.confidence
        )
        print("✅ Sample created: \(sample)")

        // Basic assertions
        #expect(frame.image.width > 0)
        #expect(frame.image.height > 0)
        #expect(detection.confidence >= 0.0 && detection.confidence <= 1.0)
    }

    @Test("Cropped water region has expected dimensions")
    func cowellsWaterRegionCrop() async throws {
        let registry = try SpotRegistry.bundled()
        guard let spot = registry.spots.first(where: { $0.id == "cowells" }) else {
            Issue.record("Cowells spot not found")
            return
        }
        let source = SnapshotSource(url: URL(string: spot.source.url)!)
        let frame = try await source.currentFrame()
        
        // The water region points are normalized (0...1)
        // For a 2448x2048 image:
        // x: 0.05*2448=122 to 0.95*2448=2325 → width ~2203
        // y: 0.45*2048=921 to 0.80*2048=1638 → height ~717
        let w = Double(frame.image.width), h = Double(frame.image.height)
        let xs = spot.waterRegion.points.map { $0.x * w }
        let ys = spot.waterRegion.points.map { $0.y * h }
        let cropWidth = xs.max()! - xs.min()!
        let cropHeight = ys.max()! - ys.min()!
        
        print("📐 Frame: \(Int(w))x\(Int(h))")
        print("📐 Water region crop: \(Int(cropWidth))x\(Int(cropHeight))")
        print("📐 Normalized points: \(spot.waterRegion.points)")
        
        #expect(cropWidth > 0)
        #expect(cropHeight > 0)
        #expect(cropWidth < w)
        #expect(cropHeight < h)
    }
}
