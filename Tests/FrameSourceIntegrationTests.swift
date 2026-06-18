import Testing
import Foundation
@testable import Swell

@Suite("FrameSource integration tests", .timeLimit(.minutes(2)))
struct FrameSourceIntegrationTests {

    @Test("SnapshotSource fetches and decodes CoastCam JPEG")
    func snapshotSource() async throws {
        let url = URL(string: "https://cmgp-coastcam.s3-us-west-2.amazonaws.com/cameras/dreaminn/latest/c2_snap.jpg")!
        let source = SnapshotSource(url: url)
        let frame = try await source.currentFrame()
        #expect(frame.image.width > 0)
        #expect(frame.image.height > 0)
        print("✅ SnapshotSource: \(frame.image.width)x\(frame.image.height) @ \(frame.timestamp)")
    }

    @Test("HLSSource grabs frame from live HLS stream (Seacliff)")
    func hlsSourceSeacliff() async throws {
        let url = URL(string: "https://video.parks.ca.gov/Seacliff/Seacliff.stream/playlist.m3u8")!
        let source = HLSSource(url: url)
        let frame = try await source.currentFrame()
        #expect(frame.image.width > 0)
        #expect(frame.image.height > 0)
        print("✅ HLSSource (Seacliff): \(frame.image.width)x\(frame.image.height) @ \(frame.timestamp)")
    }

    @Test("HLSSource grabs frame from SC Wharf stream")
    func hlsSourceSCWharf() async throws {
        let url = URL(string: "https://stage-ams.srv.axds.co/stream/adaptive/cencoos/santacruzwharf/hls.m3u8")!
        let source = HLSSource(url: url)
        let frame = try await source.currentFrame()
        #expect(frame.image.width > 0)
        #expect(frame.image.height > 0)
        print("✅ HLSSource (SC Wharf): \(frame.image.width)x\(frame.image.height) @ \(frame.timestamp)")
    }
}
