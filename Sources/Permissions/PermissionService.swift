import Foundation
import EventKit
import CoreLocation

/// Protocol for requesting calendar and location permissions — swappable for testing.
@MainActor
protocol PermissionService: Sendable {
    /// Requests both calendar and location permissions.
    /// Returns a tuple of (calendarGranted, locationGranted).
    func requestAllPermissions() async -> (calendar: Bool, location: Bool)

    /// Requests calendar permission only.
    func requestCalendarAccess() async -> Bool

    /// Requests location permission only.
    func requestLocationAccess() async -> Bool

    /// Current calendar authorization status.
    var calendarAuthorizationStatus: EKAuthorizationStatus { get }

    /// Current location authorization status.
    var locationAuthorizationStatus: CLAuthorizationStatus { get }

    /// Whether the app has full calendar access.
    var hasCalendarAccess: Bool { get }

    /// Whether the app has location access (when in use).
    var hasLocationAccess: Bool { get }
}

/// Errors that can occur when requesting permissions.
enum PermissionError: LocalizedError, Sendable {
    case calendarAccessDenied
    case calendarAccessRestricted
    case locationAccessDenied
    case locationAccessRestricted

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            return "Calendar access was denied. Enable in System Settings → Privacy & Security → Calendars."
        case .calendarAccessRestricted:
            return "Calendar access is restricted (e.g., by MDM profile)."
        case .locationAccessDenied:
            return "Location access was denied. Enable in System Settings → Privacy & Security → Location Services."
        case .locationAccessRestricted:
            return "Location access is restricted (e.g., by MDM profile)."
        }
    }
}

/// EventKit + CoreLocation-backed implementation of PermissionService.
@MainActor
final class SystemPermissionService: PermissionService, ObservableObject {
    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()

    // Cache the initial statuses so we can detect changes
    private var _calendarStatus: EKAuthorizationStatus = .notDetermined
    private var _locationStatus: CLAuthorizationStatus = .notDetermined

    init() {
        _calendarStatus = EKEventStore.authorizationStatus(for: .event)
        _locationStatus = locationManager.authorizationStatus
    }

    var calendarAuthorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    var hasCalendarAccess: Bool {
        calendarAuthorizationStatus == .fullAccess
    }

    var hasLocationAccess: Bool {
        #if os(macOS)
        locationAuthorizationStatus == .authorizedAlways
        #else
        locationAuthorizationStatus == .authorizedWhenInUse || locationAuthorizationStatus == .authorizedAlways
        #endif
    }

    func requestAllPermissions() async -> (calendar: Bool, location: Bool) {
        async let calendarResult = requestCalendarAccess()
        async let locationResult = requestLocationAccess()
        return await (calendarResult, locationResult)
    }

    func requestCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return true
        case .notDetermined:
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    func requestLocationAccess() async -> Bool {
        let status = locationManager.authorizationStatus
        switch status {
        #if os(macOS)
        case .authorizedAlways:
            return true
        #else
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        #endif
        case .notDetermined:
            // Request location access - this shows the system dialog
            locationManager.requestWhenInUseAuthorization()
            // Wait a bit for the user to respond
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            let newStatus = locationManager.authorizationStatus
            #if os(macOS)
            return newStatus == .authorizedAlways
            #else
            return newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways
            #endif
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

/// A no-op permission service for previews and tests.
@MainActor
final class PreviewPermissionService: PermissionService {
    let calendarAuthorizationStatus: EKAuthorizationStatus = .fullAccess
    #if os(macOS)
    let locationAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways
    #else
    let locationAuthorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    #endif
    let hasCalendarAccess: Bool = true
    let hasLocationAccess: Bool = true

    func requestAllPermissions() async -> (calendar: Bool, location: Bool) {
        (true, true)
    }

    func requestCalendarAccess() async -> Bool { true }

    func requestLocationAccess() async -> Bool { true }
}