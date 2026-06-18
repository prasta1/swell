import SwiftUI

/// The swell/tide/wind strip at the top of the dropdown.
struct ConditionsStrip: View {
    let c: Conditions?

    var body: some View {
        HStack(spacing: 6) {
            cell("Swell", c?.swellHeightFt.map { String(format: "%.1fft", $0) } ?? "—",
                 c?.swellPeriodS.map { String(format: "%.0fs", $0) })
            cell("Tide", c?.tideFt.map { String(format: "%.1fft", $0) } ?? "—",
                 c?.tideRising.map { $0 ? "rising" : "falling" })
            cell("Wind", c?.windMph.map { String(format: "%.0f", $0) } ?? "—",
                 c?.windOffshore.map { $0 ? "offshore" : "onshore" })
        }
    }

    private func cell(_ label: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value + (sub.map { " " + $0 } ?? "")).font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
