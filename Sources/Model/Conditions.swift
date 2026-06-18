import Foundation

/// A snapshot of surf conditions, fetched on a slower cadence than crowd counts
/// and attached to each sample. All fields optional — any API can be down
/// without blocking the rest.
struct Conditions: Codable, Equatable {
    var swellHeightFt: Double?
    var swellPeriodS: Double?
    var tideFt: Double?
    var tideRising: Bool?
    var windMph: Double?
    var windOffshore: Bool?
    var fetchedAt: Date
}

/// Crowd level relative to what's typical for this spot at this weekday/hour.
enum TrendLevel: Equatable { case quiet, typical, busy, unknown }
