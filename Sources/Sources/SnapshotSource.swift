import Foundation
import ImageIO

/// Fetches a single JPEG snapshot over HTTP (e.g. the Dream Inn CoastCam stills).
struct SnapshotSource: FrameSource {
    let url: URL

    func currentFrame() async throws -> FrameResult {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FrameSourceError.unreachable
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw FrameSourceError.decodeFailed
        }
        // Snapshot cams burn a timestamp into the image; we don't OCR it, so use
        // fetch time. The UI labels these "snapshot" so staleness stays visible.
        return FrameResult(image: img, timestamp: Date())
    }
}
