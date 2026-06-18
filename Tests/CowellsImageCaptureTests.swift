import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Swell

@Suite("Cowells image capture for visual inspection", .timeLimit(.minutes(2)))
struct CowellsImageCaptureTests {

    @Test("Save Cowells frame to disk for visual inspection")
    func saveCowellsFrame() async throws {
        let registry = try SpotRegistry.bundled()
        guard let spot = registry.spots.first(where: { $0.id == "cowells" }) else {
            Issue.record("Cowells spot not found")
            return
        }
        let source = SnapshotSource(url: URL(string: spot.source.url)!)
        let frame = try await source.currentFrame()
        
        // Save to temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("cowells_capture_\(Int(frame.timestamp.timeIntervalSince1970)).png")
        
        guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            Issue.record("Failed to create image destination")
            return
        }
        CGImageDestinationAddImage(dest, frame.image, nil)
        guard CGImageDestinationFinalize(dest) else {
            Issue.record("Failed to write PNG")
            return
        }
        
        print("💾 Saved frame to: \(fileURL.path)")
        print("📐 Frame: \(frame.image.width)x\(frame.image.height)")
        print("⏰ Timestamp: \(frame.timestamp)")
        print("🌊 Water region (normalized): \(spot.waterRegion.points)")
        
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
