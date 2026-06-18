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

    /// Status of the "Go Surf" flow.
    enum SurfEscapeStatus: Equatable {
        case idle
        case requestingPermission
        case generatingTitle
        case creatingEvent
        case success(String)   // The generated title
        case failure(String)   // Error message
    }

    @Published var rows: [Row] = []
    @Published var conditions: Conditions?
    @Published var selectedDuration: TimeInterval? = 3600  // Default 1 hour
    @Published var surfEscapeStatus: SurfEscapeStatus = .idle

    private let registry: SpotRegistry
    private let store: HistoryStore
    private let calendarService: CalendarService
    private let titleGenerator: MeetingTitleGenerator

    init(registry: SpotRegistry, store: HistoryStore, calendarService: CalendarService, titleGenerator: MeetingTitleGenerator) {
        self.registry = registry
        self.store = store
        self.calendarService = calendarService
        self.titleGenerator = titleGenerator
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

    /// Initiates the "Go Surf" flow: generates a title and creates a calendar event.
    func goSurf() {
        guard let duration = selectedDuration else { return }
        surfEscapeStatus = .requestingPermission

        Task {
            // Request calendar access if needed
            let granted = await calendarService.requestAccess()
            guard granted else {
                surfEscapeStatus = .failure("Calendar access denied. Enable in System Settings → Privacy & Security → Calendars.")
                return
            }

            surfEscapeStatus = .generatingTitle
            let title = await titleGenerator.generateTitle()

            surfEscapeStatus = .creatingEvent
            do {
                try await calendarService.createEvent(duration: duration, title: title)
                surfEscapeStatus = .success(title)
                // Auto-clear success after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .success = surfEscapeStatus {
                    surfEscapeStatus = .idle
                }
            } catch let error as CalendarError {
                surfEscapeStatus = .failure(error.localizedDescription)
            } catch {
                surfEscapeStatus = .failure("Unexpected error: \(error.localizedDescription)")
            }
        }
    }
}
