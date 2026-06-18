import Foundation

/// Observable state for the dropdown. Reads the latest sample and the weekday×hour
/// baseline per spot and turns them into display rows.
@MainActor
final class MenuViewModel: ObservableObject {
    struct Row: Identifiable {
        var id: String
        var name: String
        var count: Int?
        var trend: TrendLevel
        var surfValue: SurfValue
        var freshness: String     // e.g. "snapshot · 11 min ago"
        var lowSignal: Bool
    }

    @Published var rows: [Row] = []
    @Published var conditions: Conditions?

    private let registry: SpotRegistry
    private let store: HistoryStore

    init(registry: SpotRegistry, store: HistoryStore) {
        self.registry = registry; self.store = store
    }

    func refresh(now: Date = Date()) {
        rows = registry.spots.map { spot in
            // Flatten the `try?` double-optionals to a single optional.
            let latest: Sample? = (try? store.latest(spotID: spot.id)) ?? nil
            let typical: Double? = (try? store.typicalCount(spotID: spot.id, for: now)) ?? nil
            let level: TrendLevel = {
                guard let c = latest?.count else { return .unknown }
                return trend(current: c, typical: typical)
            }()
            return Row(
                id: spot.id, name: spot.name,
                count: latest?.count, trend: level, surfValue: spot.surfValue,
                freshness: freshnessLabel(spot: spot, sample: latest, now: now),
                lowSignal: spot.surfValue == .lowSignal
            )
        }
    }

    private func freshnessLabel(spot: Spot, sample: Sample?, now: Date) -> String {
        guard let sample else {
            return spot.surfValue == .locked ? "no public cam — source pluggable later" : "—"
        }
        let mins = Int(now.timeIntervalSince(sample.timestamp) / 60)
        let kind = spot.source.kind == .snapshot ? "snapshot" : "live"
        return "\(kind) · \(mins) min ago"
    }
}
