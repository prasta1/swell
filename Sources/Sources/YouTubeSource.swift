import Foundation
import ImageIO

/// Fetches a live-stream frame from a YouTube live cam via the periodic-thumbnail
/// endpoint YouTube generates for active live streams. Thumbnails update roughly
/// every 30 seconds — well within the app's 15-minute sampling cadence.
///
/// Pass the standard YouTube watch URL (https://www.youtube.com/watch?v=VIDEO_ID).
/// Returns nil from init if the URL lacks a "v" query parameter.
struct YouTubeSource: FrameSource {
    let videoID: String

    init?(watchURL: URL) {
        guard let id = URLComponents(url: watchURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value else { return nil }
        videoID = id
    }

    /// The live-thumbnail URL for this stream. Only returns a current frame while
    /// the stream is active; returns HTTP 404 when the stream is offline.
    var thumbnailURL: URL {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/maxresdefault_live.jpg")!
    }

    func currentFrame() async throws -> FrameResult {
        let (data, response) = try await URLSession.shared.data(from: thumbnailURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FrameSourceError.unreachable
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw FrameSourceError.decodeFailed
        }
        return FrameResult(image: img, timestamp: Date())
    }
}
