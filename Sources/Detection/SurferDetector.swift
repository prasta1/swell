import CoreGraphics

/// Counts surfers within a cam's water region. Behind a protocol so the Core ML
/// implementation can be swapped (e.g. for a permissively-licensed model) later.
protocol SurferDetector {
    func count(in frame: CGImage, region: WaterRegion) throws -> Detection
}
