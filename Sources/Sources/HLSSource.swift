import Foundation
import AVFoundation

/// Grabs a single frame from a live HLS stream's current edge.
struct HLSSource: FrameSource {
    let url: URL

    func currentFrame() async throws -> FrameResult {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        // Wide tolerance lets the generator return the current live edge rather
        // than failing to find an exact PTS in a sliding live playlist.
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        do {
            let cg = try await image(from: gen, at: .zero)
            return FrameResult(image: cg, timestamp: Date())
        } catch {
            throw FrameSourceError.unreachable
        }
    }

    private func image(from gen: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { cont in
            gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, error in
                if let image { cont.resume(returning: image) }
                else { cont.resume(throwing: error ?? FrameSourceError.unreachable) }
            }
        }
    }
}
