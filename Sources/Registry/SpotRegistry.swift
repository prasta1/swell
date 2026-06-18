import Foundation

/// Loads the configured cam list. Decodes a bundled `spots.json` describing each
/// spot, its frame source, water-region polygon, and surf value.
struct SpotRegistry {
    let spots: [Spot]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        spots = try JSONDecoder().decode([Spot].self, from: data)
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
}
