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

    static func parseTide(_ data: Data) -> TideReading {
        struct P: Decodable { let t: String; let v: String }
        struct Root: Decodable { let predictions: [P] }
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let last = root.predictions.last, let v = Double(last.v) else {
            return .init(ft: nil, rising: nil)
        }
        var rising: Bool? = nil
        if root.predictions.count >= 2,
           let prev = Double(root.predictions[root.predictions.count - 2].v) {
            rising = v > prev
        }
        return .init(ft: v, rising: rising)
    }

    static func parseWind(_ data: Data) -> WindReading {
        struct Val: Decodable { let value: Double? }
        struct Props: Decodable { let windSpeed: Val; let windDirection: Val }
        struct Root: Decodable { let properties: Props }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else {
            return .init(mph: nil, offshore: nil)
        }
        let mph = root.properties.windSpeed.value.map { $0 * 2.236936 }   // m/s → mph
        let offshore = root.properties.windDirection.value.map(isOffshore(fromDegrees:))
        return .init(mph: mph, offshore: offshore)
    }

    // MARK: - Live fetch (integration; URLs are spec open item 4)

    func fetch() async -> Conditions {
        async let ndbc = data("https://www.ndbc.noaa.gov/data/realtime2/46042.txt")
        async let tide = data("https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&datum=MLLW&time_zone=lst_ldt&interval=6&units=english&format=json&station=9413745&begin_date=today&range=24")
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
    private func parseTideSafe(_ d: Data?) -> TideReading { d.map(Self.parseTide) ?? .init(ft: nil, rising: nil) }
    private func parseWindSafe(_ d: Data?) -> WindReading { d.map(Self.parseWind) ?? .init(mph: nil, offshore: nil) }
}
