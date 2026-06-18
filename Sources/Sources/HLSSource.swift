import Foundation
import AVFoundation
import CoreMedia
import CoreImage

/// Grabs a single frame from a live HLS stream using AVPlayerItemVideoOutput.
/// More robust for live streams than AVAssetImageGenerator because it hooks
/// into the playback pipeline and can grab the "current" frame at the live edge.
struct HLSSource: FrameSource {
    let url: URL

    func currentFrame() async throws -> FrameResult {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)

        // Configure video output for frame capture
        let outputSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let videoOutput = AVPlayerItemVideoOutput(outputSettings: outputSettings)
        playerItem.add(videoOutput)

        // Start playback and wait for first frame
        player.play()

        // Wait for the player to be ready and have a frame at the live edge
        let frame = try await waitForFrame(videoOutput: videoOutput, playerItem: playerItem, timeout: 10.0)

        player.pause()
        playerItem.remove(videoOutput)

        return FrameResult(image: frame, timestamp: Date())
    }

    private func waitForFrame(videoOutput: AVPlayerItemVideoOutput, playerItem: AVPlayerItem, timeout: TimeInterval) async throws -> CGImage {
        let startTime = CACurrentMediaTime()

        while CACurrentMediaTime() - startTime < timeout {
            // Check if player item is ready
            if playerItem.status == .readyToPlay,
               videoOutput.hasNewPixelBuffer(forItemTime: playerItem.currentTime()) {

                guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: playerItem.currentTime(), itemTimeForDisplay: nil) else {
                    throw FrameSourceError.decodeFailed
                }

                // Convert CVPixelBuffer to CGImage
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                    throw FrameSourceError.decodeFailed
                }
                return cgImage
            }

            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        throw FrameSourceError.unreachable
    }
}
