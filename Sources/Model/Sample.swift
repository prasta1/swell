import Foundation

/// One detector result. `count` is nil when the detector could not produce a
/// reading (so the UI shows "—" instead of a misleading 0).
struct Detection: Equatable {
    var count: Int?
    var confidence: Double   // 0...1 mean box confidence
}

/// One persisted sample for a spot at a point in time. `timestamp` is the
/// frame's best-known capture time, not the fetch time, so stale snapshots read
/// honestly in the UI.
struct Sample: Equatable {
    var spotID: String
    var timestamp: Date
    var count: Int?
    var confidence: Double
}
