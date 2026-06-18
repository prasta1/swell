import SwiftUI

/// One spot's row: name, freshness, count, and the trend chip. Locked gap-spots
/// and low-signal beach cams get muted treatment.
struct SpotRow: View {
    let row: MenuViewModel.Row
    /// Opens the cam-viewer window focused on this spot.
    let onViewCam: (String) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: 14, weight: .medium))
                Text(row.freshness).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            if row.surfValue == .locked {
                Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(.tertiary)
                Text("—").foregroundStyle(.tertiary)
            } else if row.lowSignal {
                Text("low signal").font(.system(size: 11)).foregroundStyle(.tertiary)
                Text(row.count.map(String.init) ?? "—").font(.system(size: 18, weight: .medium))
            } else {
                trendChip(row.trend)
                Text(row.count.map(String.init) ?? "—").font(.system(size: 18, weight: .medium))
            }
        }
        .opacity(row.surfValue == .locked ? 0.45 : (row.lowSignal ? 0.65 : 1))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contextMenu {
            if row.sourceKind != .youtube && row.surfValue != .locked {
                Button("View Live Cam") { onViewCam(row.id) }
                if let url = row.camURL {
                    Button("Open Cam in Browser") { openURL(url) }
                }
            } else {
                Button("No public cam") {}.disabled(true)
            }
        }
    }

    @ViewBuilder private func trendChip(_ t: TrendLevel) -> some View {
        switch t {
        case .quiet:   chip("emptier than usual", .green)
        case .typical: chip("about typical", .orange)
        case .busy:    chip("busier than usual", .red)
        case .unknown: chip("no baseline yet", .gray)
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
