import Foundation
import EventKit

/// Protocol for creating calendar events — swappable for testing.
/// All operations run on the main actor because EventKit requires it.
@MainActor
protocol CalendarService: Sendable {
    /// Requests calendar access. Returns true if granted.
    func requestAccess() async -> Bool

    /// Whether the app currently has calendar write access.
    var isAuthorized: Bool { get }

    /// Creates an event starting now with the given duration and title.
    /// - Parameters:
    ///   - duration: Event length in seconds.
    ///   - title: The event title (e.g., "Underwater Basket Weaving").
    /// - Throws: CalendarError if access denied or save fails.
    func createEvent(duration: TimeInterval, title: String) async throws
}

/// Errors that can occur when interacting with the calendar.
enum CalendarError: LocalizedError, Sendable {
    case accessDenied
    case accessRestricted
    case saveFailed(Error)
    case noDefaultCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Enable in System Settings → Privacy & Security → Calendars."
        case .accessRestricted:
            return "Calendar access is restricted (e.g., by MDM profile)."
        case .saveFailed(let err):
            return "Failed to save event: \(err.localizedDescription)"
        case .noDefaultCalendar:
            return "No default calendar available. Add a calendar in Calendar.app first."
        }
    }
}

/// EventKit-backed implementation of CalendarService.
@MainActor
final class EventKitCalendarService: CalendarService {
    private let store = EKEventStore()
    private var _isAuthorized: Bool = false

    var isAuthorized: Bool { _isAuthorized }

    init() {
        _isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            _isAuthorized = true
            return true
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                _isAuthorized = granted
                return granted
            } catch {
                _isAuthorized = false
                return false
            }
        case .denied, .restricted, .writeOnly:
            _isAuthorized = false
            return false
        @unknown default:
            _isAuthorized = false
            return false
        }
    }

    func createEvent(duration: TimeInterval, title: String) async throws {
        // Ensure we have authorization before proceeding
        if !_isAuthorized {
            let granted = await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }

        // Use the default calendar for new events
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarError.noDefaultCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(duration)
        event.calendar = calendar
        // No alarms, no attendees, no location (v1)

        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw CalendarError.saveFailed(error)
        }
    }
}