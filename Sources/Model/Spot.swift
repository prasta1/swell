import Foundation

/// A point in a cam's water-region polygon, stored as normalized coordinates
/// (0...1 in both axes) so a region survives changes in frame resolution.
struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x); try c.encode(y)
    }
}

/// The polygon marking where surfers appear in a cam's frame. Detection runs
/// only inside this region so beach/cliff/parking-lot people are ignored.
struct WaterRegion: Codable, Equatable {
    var points: [NormalizedPoint]
}

enum SourceKind: String, Codable { case snapshot, hls, youtube }

/// How to fetch a cam's current frame. `youtube` is a placeholder kind for the
/// locked gap-spots; the pluggable `FrameSource` layer gains a real impl later.
struct SourceDescriptor: Codable, Equatable {
    var kind: SourceKind
    var url: String
}

/// How useful a cam is for reading a surf lineup, which drives UI treatment.
/// `lowSignal` cams mostly show beach; `locked` spots have no public cam.
enum SurfValue: String, Codable { case good, ok, lowSignal, locked }

struct Spot: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var source: SourceDescriptor
    var waterRegion: WaterRegion
    var surfValue: SurfValue
}
