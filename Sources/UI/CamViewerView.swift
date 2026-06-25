import SwiftUI
import AVKit

/// Shared state for the cam-viewer window: the spots it can show, the detector
/// used for the on-demand overlay, and the current selection. Owned by
/// `SwellApp`; the menubar sets `selectedSpotID` before opening the window.
@MainActor
final class CamViewerModel: ObservableObject {
    @Published var spots: [Spot]
    let detector: SurferDetector
    @Published var selectedSpotID: String?

    init(spots: [Spot], detector: SurferDetector) {
        self.spots = spots
        self.detector = detector
    }

    /// Spots that actually have a viewable feed (excludes locked spots and YouTube
    /// placeholder entries that have no URL yet).
    var viewableSpots: [Spot] {
        spots.filter { $0.surfValue != .locked && ($0.source.kind != .youtube || !$0.source.url.isEmpty) }
    }

    /// Persists a tuned water region for the given spot and updates the in-memory
    /// list immediately so the overlay reflects the change without a relaunch.
    func saveWaterRegion(_ region: WaterRegion, forSpotID spotID: String) {
        SpotRegistry.saveWaterRegion(region, forSpotID: spotID)
        if let i = spots.firstIndex(where: { $0.id == spotID }) {
            spots[i].waterRegion = region
        }
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
                    .padding(.vertical, 3)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            if let spot = selectedSpot {
                CamFeedView(spot: spot, mode: mode, detector: model.detector,
                            onSaveRegion: { model.saveWaterRegion($0, forSpotID: spot.id) })
                    .id(spot.id)   // tear down/rebuild the player or analysis on spot change
                    .navigationTitle(spot.name)
            } else {
                ContentUnavailableView("Select a cam", systemImage: "video")
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .toolbar {
            if let spot = selectedSpot, spot.surfValue != .locked {
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
        switch spot.source.kind {
        case .hls:      "video"
        case .youtube:  "play.rectangle"
        case .snapshot: "photo"
        }
    }
}

/// Routes to the live feed or the detection overlay for the selected spot.
private struct CamFeedView: View {
    let spot: Spot
    let mode: FeedMode
    let detector: SurferDetector
    let onSaveRegion: (WaterRegion) -> Void

    var body: some View {
        if spot.source.kind == .youtube && spot.source.url.isEmpty {
            ContentUnavailableView("Preview unavailable", systemImage: "video.slash",
                                   description: Text("This spot has no public cam feed yet."))
        } else {
            switch mode {
            case .live:       liveView
            case .detections: DetectionOverlayView(spot: spot, detector: detector,
                                                   onSaveRegion: onSaveRegion)
            }
        }
    }

    @ViewBuilder private var liveView: some View {
        switch spot.source.kind {
        case .hls:      HLSFeedView(url: URL(string: spot.source.url))
        case .snapshot: SnapshotFeedView(url: URL(string: spot.source.url))
        case .youtube:  YouTubeFeedView(watchURLString: spot.source.url)
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

/// YouTube live cams: calls YouTubeSource.currentFrame() which tries the live
/// thumbnail first, then falls back to the static poster. Refreshes every 60s.
private struct YouTubeFeedView: View {
    let watchURLString: String
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
        .task(id: watchURLString) {
            guard let watchURL = URL(string: watchURLString),
                  let source = YouTubeSource(watchURL: watchURL) else {
                errorMessage = "Invalid YouTube URL."
                return
            }
            while !Task.isCancelled {
                do {
                    let frame = try await source.currentFrame()
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
    let onSaveRegion: (WaterRegion) -> Void

    @State private var image: CGImage?
    @State private var detection: Detection?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var isEditingRegion = false
    @State private var editablePoints: [NormalizedPoint] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
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
                if isEditingRegion {
                    RegionEditorOverlay(points: $editablePoints, frameRect: fit)
                        .frame(width: fit.width, height: fit.height)
                } else {
                    WaterRegionShape(points: spot.waterRegion.points)
                        .stroke(Color.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: fit.width, height: fit.height)
                }
                // Detection boxes always rendered so results are visible while editing
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
        HStack(spacing: 10) {
            if isEditingRegion {
                Text("\(editablePoints.count) points")
                    .font(.system(size: 12, weight: .medium))
                Text("· drag to move  ·  click ◦ to add  ·  right-click to remove")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if isAnalyzing {
                    ProgressView().controlSize(.small)
                } else if let detection {
                    let n = detection.count ?? 0
                    Image(systemName: "figure.surfing").foregroundStyle(.green)
                    Text("\(n) surfer\(n == 1 ? "" : "s")").font(.system(size: 12, weight: .medium))
                }
                Spacer()
                Button { Task { await analyze() } } label: {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                }
                .disabled(isAnalyzing)
                Button("Cancel") { isEditingRegion = false }
                Button("Save Region") {
                    let region = WaterRegion(points: editablePoints)
                    onSaveRegion(region)
                    isEditingRegion = false
                }
                .buttonStyle(.borderedProminent)
            } else {
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
                if image != nil {
                    Button {
                        editablePoints = spot.waterRegion.points
                        detection = nil   // clear boxes from old region
                        isEditingRegion = true
                    } label: {
                        Label("Edit Region", systemImage: "pencil.and.outline")
                    }
                    .disabled(isAnalyzing)
                }
                Button { Task { await analyze() } } label: {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                }
                .disabled(isAnalyzing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @MainActor private func analyze() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        guard let url = URL(string: spot.source.url) else { errorMessage = "Invalid cam URL."; return }
        let source: FrameSource
        switch spot.source.kind {
        case .hls:      source = HLSSource(url: url)
        case .youtube:  source = YouTubeSource(watchURL: url) ?? SnapshotSource(url: url)
        case .snapshot: source = SnapshotSource(url: url)
        }
        do {
            let frame = try await source.currentFrame()
            // Tiled detection is several inferences; run it off the main actor.
            let detector = self.detector
            let region = isEditingRegion ? WaterRegion(points: editablePoints) : spot.waterRegion
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

/// Drag-to-edit polygon overlay. Vertex handles (●) drag to reposition; midpoint
/// dots (◦) tap to insert a new vertex; right-click a handle to delete it.
/// Changes write back via the binding — copy the JSON from the status bar and
/// paste into spots.json to persist.
private struct RegionEditorOverlay: View {
    @Binding var points: [NormalizedPoint]
    let frameRect: CGRect

    @State private var dragStart: [Int: NormalizedPoint] = [:]

    private let handleR: CGFloat = 7
    private let midR:    CGFloat = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Polygon outline — solid while editing
            WaterRegionShape(points: points)
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: frameRect.width, height: frameRect.height)

            // Edge midpoints — tap to insert a vertex between two neighbours
            ForEach(0..<points.count, id: \.self) { i in
                let j  = (i + 1) % points.count
                let mx = (points[i].x + points[j].x) / 2
                let my = (points[i].y + points[j].y) / 2
                Circle()
                    .fill(Color.yellow.opacity(0.35))
                    .stroke(Color.yellow.opacity(0.75), lineWidth: 1)
                    .frame(width: midR * 2, height: midR * 2)
                    .offset(x: mx * frameRect.width  - midR,
                            y: my * frameRect.height - midR)
                    .onTapGesture {
                        points.insert(NormalizedPoint(x: mx, y: my), at: i + 1)
                    }
            }

            // Vertex drag handles
            ForEach(0..<points.count, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: handleR * 2, height: handleR * 2)
                    .offset(x: points[i].x * frameRect.width  - handleR,
                            y: points[i].y * frameRect.height - handleR)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard frameRect.width > 0, frameRect.height > 0 else { return }
                                if dragStart[i] == nil { dragStart[i] = points[i] }
                                guard let s = dragStart[i] else { return }
                                points[i] = NormalizedPoint(
                                    x: max(0, min(1, s.x + v.translation.width  / frameRect.width)),
                                    y: max(0, min(1, s.y + v.translation.height / frameRect.height))
                                )
                            }
                            .onEnded { _ in dragStart[i] = nil }
                    )
                    .contextMenu {
                        if points.count > 3 {
                            Button("Delete point", role: .destructive) {
                                points.remove(at: i)
                            }
                        }
                    }
            }
        }
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
