import Foundation

/// Loads the configured cam list. Decodes a bundled `spots.json` describing each
/// spot, its frame source, water-region polygon, and surf value.
///
/// Water-region overrides edited in the cam viewer are persisted to UserDefaults
/// under `waterRegionOverridesKey` and applied on top of the bundle defaults at
/// load time, so tuned regions survive rebuilds without touching the source file.
struct SpotRegistry {
    let spots: [Spot]

    static let waterRegionOverridesKey = "com.peregrine.Swell.waterRegionOverrides"

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        var loaded = try JSONDecoder().decode([Spot].self, from: data)
        // Merge any saved water-region overrides on top of bundle defaults.
        if let raw = UserDefaults.standard.dictionary(forKey: SpotRegistry.waterRegionOverridesKey) {
            loaded = loaded.map { spot in
                guard let pts = raw[spot.id] as? [[Double]] else { return spot }
                let overridePoints = pts.compactMap { p -> NormalizedPoint? in
                    guard p.count == 2 else { return nil }
                    return NormalizedPoint(x: p[0], y: p[1])
                }
                var updated = spot
                updated.waterRegion = WaterRegion(points: overridePoints)
                return updated
            }
        }
        spots = loaded
    }

    /// Spots with a usable public source. Locked gap-spots (no public cam) are
    /// shown in the UI but never sampled.
    var activeSpots: [Spot] {
        spots.filter { $0.surfValue != .locked }
    }

    /// Loads the registry bundled with the app.
    static func bundled() throws -> SpotRegistry {
        let url = Bundle.main.url(forResource: "spots", withExtension: "json")!
        return try SpotRegistry(url: url)
    }

    /// Persists a water-region override for the given spot ID. The change
    /// takes effect immediately in any live CamViewerModel and is reloaded
    /// from UserDefaults on the next launch. To commit the change permanently,
    /// update the corresponding entry in spots.json.
    static func saveWaterRegion(_ region: WaterRegion, forSpotID spotID: String) {
        var overrides = (UserDefaults.standard.dictionary(forKey: waterRegionOverridesKey) ?? [:])
        overrides[spotID] = region.points.map { [$0.x, $0.y] }
        UserDefaults.standard.set(overrides, forKey: waterRegionOverridesKey)
    }
}
