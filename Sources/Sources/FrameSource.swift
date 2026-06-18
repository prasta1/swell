import CoreGraphics
import Foundation

/// A fetched frame plus its best-known capture time.
struct FrameResult {
    var image: CGImage
    var timestamp: Date
}

enum FrameSourceError: Error { case unreachable, decodeFailed, notImplemented }

/// Pluggable cam-frame acquisition. Implementations: `SnapshotSource` (JPEG GET),
/// `HLSSource` (live-stream frame grab). A future `YouTubeSource` slots in here
/// with no change to the rest of the app.
protocol FrameSource {
    /// Fetch the current frame for a cam. Throws on network/decode failure.
    func currentFrame() async throws -> FrameResult
}
