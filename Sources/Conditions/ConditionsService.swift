import Foundation

/// Fetches and parses free public surf-conditions feeds: NDBC buoy (swell),
/// NOAA CO-OPS (tide), and NWS (wind). Parsers are pure and unit-tested; the
/// live `fetch()` is best-effort and never blocks the crowd-count path.
final class ConditionsService {
    struct SwellReading { var heightFt: Double?; var periodS: Double? }
    struct TideReading { var ft: Double?; var rising: Bool? }
    struct WindReading { var mph: Double?; var offshore: Bool? }

    /// Santa Cruz inner-bay coastline faces roughly south; wind blowing FROM the
    /// northern half (off the land) is offshore and grooms the surf.
    static func isOffshore(fromDegrees deg: Double) -> Bool {
        (deg >= 250 && deg <= 360) || (deg >= 0 && deg < 110)
    }

    static func parseNDBC(_ data: Data) -> SwellReading {
        guard let text = String(data: data, encoding: .utf8) else { return .init(heightFt: nil, periodS: nil) }
        let rows = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        guard let first = rows.first else { return .init(heightFt: nil, periodS: nil) }
        let cols = first.split(whereSeparator: { $0 == " " }).map(String.init)
        guard cols.count > 9 else { return .init(heightFt: nil, periodS: nil) }
        let wvht = Double(cols[8])     // WVHT, meters
        let dpd = Double(cols[9])      // DPD, seconds
        return .init(heightFt: wvht.map { $0 * 3.28084 }, periodS: dpd)
    }

    /// Parses CO-OPS 6-minute predictions and returns the one nearest `now`
    /// (the feed covers the whole day, so the last row is end-of-day, not current).
    /// Rising/falling is the slope against the preceding 6-minute prediction.
    static func parseTide(_ data: Data, now: Date = Date()) -> TideReading {
        struct P: Decodable { let t: String; let v: String }
        struct Root: Decodable { let predictions: [P] }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              !root.predictions.isEmpty else {
            return .init(ft: nil, rising: nil)
        }
        let preds = root.predictions

        // Timestamps are local (lst_ldt); parse in the device's current zone.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        // Find the prediction closest in time to `now`.
        var bestIndex = 0
        var bestDelta = Double.greatestFiniteMagnitude
        for (i, p) in preds.enumerated() {
            guard let date = formatter.date(from: p.t) else { continue }
            let delta = abs(date.timeIntervalSince(now))
            if delta < bestDelta { bestDelta = delta; bestIndex = i }
        }

        guard let v = Double(preds[bestIndex].v) else { return .init(ft: nil, rising: nil) }
        var rising: Bool? = nil
        if bestIndex > 0, let prev = Double(preds[bestIndex - 1].v) {
            rising = v > prev
        } else if bestIndex + 1 < preds.count, let next = Double(preds[bestIndex + 1].v) {
            rising = next > v
        }
        return .init(ft: v, rising: rising)
    }

    /// Parses the NWS `/forecast/hourly` feed. Each period reports `windSpeed`
    /// as a string already in mph ("6 mph", sometimes "5 to 10 mph") and
    /// `windDirection` as a compass abbreviation ("SSW"). We read the first
    /// (current-hour) period.
    static func parseWind(_ data: Data) -> WindReading {
        struct Period: Decodable { let windSpeed: String?; let windDirection: String? }
        struct Props: Decodable { let periods: [Period] }
        struct Root: Decodable { let properties: Props }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let current = root.properties.periods.first else {
            return .init(mph: nil, offshore: nil)
        }
        // Take the leading number of "6 mph" / "5 to 10 mph"; value is already mph.
        let mph = current.windSpeed
            .flatMap { $0.split(separator: " ").first }
            .flatMap { Double($0) }
        let offshore = current.windDirection
            .flatMap(compassToDegrees)
            .map(isOffshore(fromDegrees:))
        return .init(mph: mph, offshore: offshore)
    }

    /// Maps a 16-point compass abbreviation (e.g. "WNW") to degrees, or nil if unknown.
    static func compassToDegrees(_ compass: String) -> Double? {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        guard let index = points.firstIndex(of: compass.uppercased()) else { return nil }
        return Double(index) * 22.5
    }

    // MARK: - Live fetch

    func fetch() async -> Conditions {
        async let ndbc = data("https://www.ndbc.noaa.gov/data/realtime2/46042.txt")
        // Station 9413450 (Monterey) — 9413745 (Santa Cruz) has no tide predictions.
        // `date=today` returns the full day at 6-min intervals; parseTide picks "now".
        async let tide = data("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&datum=MLLW&time_zone=lst_ldt&interval=6&units=english&format=json&station=9413450&date=today")
        async let wind = data("https://api.weather.gov/gridpoints/MTR/97,82/forecast/hourly")
        let s = parseNDBCSafe(await ndbc)
        let t = parseTideSafe(await tide)
        let w = parseWindSafe(await wind)
        return Conditions(swellHeightFt: s.heightFt, swellPeriodS: s.periodS,
                          tideFt: t.ft, tideRising: t.rising,
                          windMph: w.mph, windOffshore: w.offshore,
                          fetchedAt: Date())
    }

    private func data(_ url: String) async -> Data? {
        guard let u = URL(string: url) else { return nil }
        return try? await URLSession.shared.data(from: u).0
    }
    private func parseNDBCSafe(_ d: Data?) -> SwellReading { d.map(Self.parseNDBC) ?? .init(heightFt: nil, periodS: nil) }
    private func parseTideSafe(_ d: Data?) -> TideReading { d.map { Self.parseTide($0) } ?? .init(ft: nil, rising: nil) }
    private func parseWindSafe(_ d: Data?) -> WindReading { d.map(Self.parseWind) ?? .init(mph: nil, offshore: nil) }
}
