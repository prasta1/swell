import Foundation

/// Daylight-gated scheduler. Every interval it walks the active cams, fetches a
/// frame, counts surfers in the water region, and appends to history. Conditions
/// are refreshed on a slower (~hourly) cadence and attached to the run.
@MainActor
final class Sampler: ObservableObject {
    private let registry: SpotRegistry
    private let store: HistoryStore
    private let detector: SurferDetector
    private let conditions: ConditionsService
    private let clock: SolarClock
    private var timer: Timer?
    private var lastConditions: Conditions?

    init(registry: SpotRegistry, store: HistoryStore, detector: SurferDetector,
         conditions: ConditionsService, clock: SolarClock = SolarClock()) {
        self.registry = registry; self.store = store; self.detector = detector
        self.conditions = conditions; self.clock = clock
    }

    func start(interval: TimeInterval = 15 * 60) {
        Task { await tick() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
    }

    /// One sampling pass. Public so the UI's "Sample now" can call it.
    func tick() async {
        guard clock.isDaylight(Date()) else { return }
        if lastConditions == nil || Date().timeIntervalSince(lastConditions!.fetchedAt) > 3600 {
            lastConditions = await conditions.fetch()
        }
        for spot in registry.activeSpots {
            let source = makeSource(spot.source)
            do {
                let frame = try await source.currentFrame()
                let det = try detector.count(in: frame.image, region: spot.waterRegion)
                try store.append(Sample(spotID: spot.id, timestamp: frame.timestamp,
                                        count: det.count, confidence: det.confidence))
            } catch {
                // System boundary: record a null reading so the UI shows "—", not 0.
                try? store.append(Sample(spotID: spot.id, timestamp: Date(),
                                         count: nil, confidence: 0))
            }
        }
        objectWillChange.send()
    }

    var conditionsSnapshot: Conditions? { lastConditions }

    private func makeSource(_ d: SourceDescriptor) -> FrameSource {
        let url = URL(string: d.url) ?? URL(string: "about:blank")!
        switch d.kind {
        case .snapshot: return SnapshotSource(url: url)
        case .hls: return HLSSource(url: url)
        case .youtube: return SnapshotSource(url: url)  // placeholder until YouTubeSource lands
        }
    }
}
