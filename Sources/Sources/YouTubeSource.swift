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

    func currentFrame() async throws -> FrameResult {
        // Try the live-frame thumbnail first (updates ~30s, only exists while streaming),
        // then fall back to the static poster (always available). This ensures the viewer
        // shows the cam even when the stream is idle between broadcasts.
        let suffixes = ["maxresdefault_live.jpg", "hqdefault_live.jpg",
                        "maxresdefault.jpg", "hqdefault.jpg"]
        for suffix in suffixes {
            let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/\(suffix)")!
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            return FrameResult(image: img, timestamp: Date())
        }
        throw FrameSourceError.unreachable
    }
}
