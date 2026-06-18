import Foundation

/// Median of a list of counts, or nil when empty.
func median(_ xs: [Int]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    let n = s.count
    if n % 2 == 1 { return Double(s[n / 2]) }
    return Double(s[n / 2 - 1] + s[n / 2]) / 2.0
}

/// Classify a current count against a typical (median) baseline.
/// Busy at ≥1.4× typical, quiet at ≤0.6×, otherwise typical.
func trend(current: Int, typical: Double?) -> TrendLevel {
    guard let typical, typical > 0 else { return .unknown }
    let ratio = Double(current) / typical
    if ratio >= 1.4 { return .busy }
    if ratio <= 0.6 { return .quiet }
    return .typical
}
