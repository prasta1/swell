import SwiftUI
import AVKit

/// Shared state for the cam-viewer window: the spots it can show and the current
/// selection. Owned by `SwellApp`; the menubar sets `selectedSpotID` before
/// opening the window, and the window's sidebar binds to it.
@MainActor
final class CamViewerModel: ObservableObject {
    let spots: [Spot]
    @Published var selectedSpotID: String?

    init(spots: [Spot]) {
        self.spots = spots
    }

    /// Spots that actually have a viewable feed (excludes locked gap-spots and
    /// the YouTube placeholder kind).
    var viewableSpots: [Spot] {
        spots.filter { $0.source.kind != .youtube && $0.surfValue != .locked }
    }
}

/// A window showing live surf-cam feeds — a sidebar of spots and the selected
/// feed in the detail area. HLS spots play live video; snapshot spots show the
/// latest still, auto-refreshed.
struct CamViewerView: View {
    @ObservedObject var model: CamViewerModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationSplitView {
            List(model.viewableSpots, selection: $model.selectedSpotID) { spot in
                Label(spot.name, systemImage: icon(for: spot))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let spot = selectedSpot {
                CamFeedView(spot: spot)
                    .id(spot.id)   // tear down/rebuild the player when the spot changes
                    .navigationTitle(spot.name)
            } else {
                ContentUnavailableView("Select a cam", systemImage: "video")
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar {
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

/// Routes to the right feed renderer for a spot's source kind.
private struct CamFeedView: View {
    let spot: Spot

    var body: some View {
        switch spot.source.kind {
        case .hls:
            HLSFeedView(url: URL(string: spot.source.url))
        case .snapshot:
            SnapshotFeedView(url: URL(string: spot.source.url))
        case .youtube:
            ContentUnavailableView("Preview unavailable", systemImage: "video.slash",
                                   description: Text("This spot has no public cam feed yet."))
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
/// These sources only update every several minutes, so polling is gentle.
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
