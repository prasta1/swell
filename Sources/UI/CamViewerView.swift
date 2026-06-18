import SwiftUI
import AVKit

/// Shared state for the cam-viewer window: the spots it can show, the detector
/// used for the on-demand overlay, and the current selection. Owned by
/// `SwellApp`; the menubar sets `selectedSpotID` before opening the window.
@MainActor
final class CamViewerModel: ObservableObject {
    let spots: [Spot]
    let detector: SurferDetector
    @Published var selectedSpotID: String?

    init(spots: [Spot], detector: SurferDetector) {
        self.spots = spots
        self.detector = detector
    }

    /// Spots that actually have a viewable feed (excludes locked gap-spots and
    /// the YouTube placeholder kind).
    var viewableSpots: [Spot] {
        spots.filter { $0.source.kind != .youtube && $0.surfValue != .locked }
    }
}

/// Which view to show for the selected cam.
private enum FeedMode: Hashable { case live, detections }

/// A window showing surf-cam feeds — a sidebar of spots and the selected feed in
/// the detail area. The toolbar toggles between the live feed and an analyzed
/// still with the water-region outline and detection boxes drawn on top.
struct CamViewerView: View {
    @ObservedObject var model: CamViewerModel
    @Environment(\.openURL) private var openURL
    @State private var mode: FeedMode = .live

    var body: some View {
        NavigationSplitView {
            List(model.viewableSpots, selection: $model.selectedSpotID) { spot in
                Label(spot.name, systemImage: icon(for: spot))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let spot = selectedSpot {
                CamFeedView(spot: spot, mode: mode, detector: model.detector)
                    .id(spot.id)   // tear down/rebuild the player or analysis on spot change
                    .navigationTitle(spot.name)
            } else {
                ContentUnavailableView("Select a cam", systemImage: "video")
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar {
            if let spot = selectedSpot, spot.source.kind != .youtube {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        Text("Live").tag(FeedMode.live)
                        Text("Detections").tag(FeedMode.detections)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            if let spot = selectedSpot, let url = URL(string: spot.source.url) {
                ToolbarItem(placement: .primaryAction) {
                    Button { openURL(url) } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                }
            }
        }
        .onAppear {
            if model.selectedSpotID == nil {
                model.selectedSpotID = model.viewableSpots.first?.id
            }
        }
    }

    private var selectedSpot: Spot? {
        model.spots.first { $0.id == model.selectedSpotID }
    }

    private func icon(for spot: Spot) -> String {
        spot.source.kind == .hls ? "video" : "photo"
    }
}

/// Routes to the live feed or the detection overlay for the selected spot.
private struct CamFeedView: View {
    let spot: Spot
    let mode: FeedMode
    let detector: SurferDetector

    var body: some View {
        if spot.source.kind == .youtube {
            ContentUnavailableView("Preview unavailable", systemImage: "video.slash",
                                   description: Text("This spot has no public cam feed yet."))
        } else {
            switch mode {
            case .live:       liveView
            case .detections: DetectionOverlayView(spot: spot, detector: detector)
            }
        }
    }

    @ViewBuilder private var liveView: some View {
        switch spot.source.kind {
        case .hls:      HLSFeedView(url: URL(string: spot.source.url))
        case .snapshot: SnapshotFeedView(url: URL(string: spot.source.url))
        case .youtube:  EmptyView()   // handled above
        }
    }
}

/// Live HLS playback via AVPlayer. Muted, auto-plays, torn down on disappear.
private struct HLSFeedView: View {
    let url: URL?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ContentUnavailableView("Invalid stream URL", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            guard let url, player == nil else { return }
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.play()
            self.player = player
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

/// Snapshot (JPEG) cams: fetch the latest still and refresh on a slow loop.
private struct SnapshotFeedView: View {
    let url: URL?
    @State private var image: CGImage?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load snapshot", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { errorMessage = "Invalid cam URL."; return }
            while !Task.isCancelled {
                do {
                    let frame = try await SnapshotSource(url: url).currentFrame()
                    image = frame.image
                    errorMessage = nil
                } catch {
                    if image == nil { errorMessage = "Cam snapshot unreachable." }
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)   // 60s
            }
        }
    }
}

/// Grabs one frame, runs the detector, and shows that frozen frame with the
/// water-region outline and per-person boxes drawn on top — so you can see
/// exactly what the count is based on.
private struct DetectionOverlayView: View {
    let spot: Spot
    let detector: SurferDetector

    @State private var image: CGImage?
    @State private var detection: Detection?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    annotatedFrame(image)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't analyze cam", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else {
                    ProgressView("Grabbing a frame…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            statusBar
        }
        .task { await analyze() }
    }

    private func annotatedFrame(_ image: CGImage) -> some View {
        GeometryReader { geo in
            let fit = fittedRect(imageWidth: image.width, imageHeight: image.height, container: geo.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                WaterRegionShape(points: spot.waterRegion.points)
                    .stroke(Color.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: fit.width, height: fit.height)
                ForEach(Array((detection?.boxes ?? []).enumerated()), id: \.offset) { _, box in
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: box.width * fit.width, height: box.height * fit.height)
                        .offset(x: box.minX * fit.width, y: box.minY * fit.height)
                }
            }
            .frame(width: fit.width, height: fit.height)
            .offset(x: fit.minX, y: fit.minY)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if isAnalyzing {
                ProgressView().controlSize(.small)
                Text("Analyzing…").foregroundStyle(.secondary)
            } else if let detection {
                let n = detection.count ?? 0
                Image(systemName: "figure.surfing").foregroundStyle(.green)
                Text("\(n) surfer\(n == 1 ? "" : "s") in the water region")
                    .font(.system(size: 12, weight: .medium))
                Text("· avg conf \(String(format: "%.2f", detection.confidence))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await analyze() } } label: {
                Label("Re-analyze", systemImage: "arrow.clockwise")
            }
            .disabled(isAnalyzing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @MainActor private func analyze() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        guard let url = URL(string: spot.source.url) else { errorMessage = "Invalid cam URL."; return }
        let source: FrameSource = spot.source.kind == .hls ? HLSSource(url: url) : SnapshotSource(url: url)
        do {
            let frame = try await source.currentFrame()
            // Tiled detection is several inferences; run it off the main actor.
            let detector = self.detector
            let region = spot.waterRegion
            let result = try await Task.detached(priority: .userInitiated) {
                try detector.count(in: frame.image, region: region)
            }.value
            image = frame.image
            detection = result
        } catch {
            errorMessage = "Couldn't grab a frame from this cam to analyze."
        }
    }
}

/// Draws a cam's water-region polygon from normalized points.
private struct WaterRegionShape: Shape {
    let points: [NormalizedPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

/// The aspect-fit rect for an image of the given pixel size inside `container`,
/// centered. Overlay coordinates are drawn relative to this rect so boxes line
/// up with the letterboxed image.
private func fittedRect(imageWidth: Int, imageHeight: Int, container: CGSize) -> CGRect {
    guard imageWidth > 0, imageHeight > 0 else { return .zero }
    let scale = min(container.width / CGFloat(imageWidth), container.height / CGFloat(imageHeight))
    let width = CGFloat(imageWidth) * scale
    let height = CGFloat(imageHeight) * scale
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2,
                  width: width, height: height)
}
