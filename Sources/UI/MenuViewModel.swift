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
        var sourceKind: SourceKind
        var camURL: URL?
    }

    /// Status of the "Go Surf" flow.
    enum SurfEscapeStatus: Equatable {
        case idle
        case requestingPermission
        case generatingTitle
        case creatingEvent
        case success(title: String, duration: TimeInterval)
        case permissionDenied  // Distinct so the UI can offer an "Open Settings" button
        case failure(String)   // Generic error message
    }

    @Published var rows: [Row] = []
    @Published var conditions: Conditions?
    @Published var selectedDuration: TimeInterval? {
        didSet {
            // Persist the pick so it's pre-selected next time the menu opens (T14).
            if let selectedDuration {
                settings.selectedDuration = selectedDuration
            }
        }
    }
    @Published var surfEscapeStatus: SurfEscapeStatus = .idle

    private let registry: SpotRegistry
    private let store: HistoryStore
    private let calendarService: CalendarService
    private let titleGenerator: MeetingTitleGenerator
    private let settings: SettingsStore

    init(registry: SpotRegistry, store: HistoryStore, calendarService: CalendarService, titleGenerator: MeetingTitleGenerator, settings: SettingsStore = .shared) {
        self.registry = registry
        self.store = store
        self.calendarService = calendarService
        self.titleGenerator = titleGenerator
        self.settings = settings
        // Initializing assignment — does not fire didSet, so we don't write back
        // the value we just read.
        self.selectedDuration = settings.selectedDuration
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
                lowSignal: spot.surfValue == .lowSignal,
                sourceKind: spot.source.kind,
                camURL: URL(string: spot.source.url)
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
                surfEscapeStatus = .permissionDenied
                return
            }

            surfEscapeStatus = .generatingTitle
            let title = await titleGenerator.generateTitle()

            surfEscapeStatus = .creatingEvent
            do {
                try await calendarService.createEvent(duration: duration, title: title)
                surfEscapeStatus = .success(title: title, duration: duration)
                // Auto-clear the success toast after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .success = surfEscapeStatus {
                    surfEscapeStatus = .idle
                }
            } catch let error as CalendarError {
                // Access can still be revoked between request and save.
                switch error {
                case .accessDenied, .accessRestricted:
                    surfEscapeStatus = .permissionDenied
                default:
                    surfEscapeStatus = .failure(error.localizedDescription)
                }
            } catch {
                surfEscapeStatus = .failure("Unexpected error: \(error.localizedDescription)")
            }
        }
    }
}
