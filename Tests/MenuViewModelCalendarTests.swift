import XCTest
@testable import Swell

// MARK: - Test doubles

/// In-memory CalendarService that records calls instead of touching EventKit.
@MainActor
final class MockCalendarService: CalendarService {
    var grantAccess = true
    var errorOnCreate: CalendarError?
    var stubCalendars: [CalendarInfo] = []

    private(set) var requestAccessCount = 0
    private(set) var createdEvents: [(duration: TimeInterval, title: String)] = []
    var isAuthorized = false

    func requestAccess() async -> Bool {
        requestAccessCount += 1
        isAuthorized = grantAccess
        return grantAccess
    }

    func createEvent(duration: TimeInterval, title: String) async throws {
        if let errorOnCreate { throw errorOnCreate }
        createdEvents.append((duration, title))
    }

    func availableCalendars() -> [CalendarInfo] { stubCalendars }
}

/// Always returns a fixed title — keeps goSurf tests deterministic.
struct StubTitleGenerator: MeetingTitleGenerator {
    let title: String
    func generateTitle() async -> String { title }
}

// MARK: - Tests

@MainActor
final class MenuViewModelCalendarTests: XCTestCase {

    func testGoSurfCreatesEventWithSelectedDurationAndTitle() async throws {
        let calendar = MockCalendarService()
        let vm = try makeVM(calendar: calendar, title: "Quarterly Sandcastle Review")
        vm.selectedDuration = 5400   // 90 minutes

        vm.goSurf()
        await waitUntil { calendar.createdEvents.count == 1 }

        XCTAssertEqual(calendar.createdEvents.first?.duration, 5400)
        XCTAssertEqual(calendar.createdEvents.first?.title, "Quarterly Sandcastle Review")
        XCTAssertEqual(vm.surfEscapeStatus, .success(title: "Quarterly Sandcastle Review", duration: 5400))
    }

    func testGoSurfDeniedAccessReportsPermissionDeniedAndCreatesNoEvent() async throws {
        let calendar = MockCalendarService()
        calendar.grantAccess = false
        let vm = try makeVM(calendar: calendar)
        vm.selectedDuration = 3600

        vm.goSurf()
        await waitUntil { vm.surfEscapeStatus == .permissionDenied }

        XCTAssertEqual(vm.surfEscapeStatus, .permissionDenied)
        XCTAssertTrue(calendar.createdEvents.isEmpty)
    }

    func testGoSurfAccessRevokedMidFlowReportsPermissionDenied() async throws {
        let calendar = MockCalendarService()
        calendar.errorOnCreate = .accessDenied   // granted, then revoked before save
        let vm = try makeVM(calendar: calendar)
        vm.selectedDuration = 3600

        vm.goSurf()
        await waitUntil { vm.surfEscapeStatus == .permissionDenied }

        XCTAssertEqual(vm.surfEscapeStatus, .permissionDenied)
        XCTAssertTrue(calendar.createdEvents.isEmpty)
    }

    func testGoSurfSurfacesCreateError() async throws {
        let calendar = MockCalendarService()
        calendar.errorOnCreate = .noDefaultCalendar
        let vm = try makeVM(calendar: calendar)
        vm.selectedDuration = 3600

        vm.goSurf()
        await waitUntil { isFailure(vm.surfEscapeStatus) }

        XCTAssertTrue(isFailure(vm.surfEscapeStatus))
        XCTAssertTrue(calendar.createdEvents.isEmpty)
    }

    func testGoSurfWithNoDurationDoesNothing() async throws {
        let calendar = MockCalendarService()
        let vm = try makeVM(calendar: calendar)
        vm.selectedDuration = nil

        vm.goSurf()
        // Nothing should be spawned; give any stray work a brief moment anyway.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(calendar.createdEvents.isEmpty)
        XCTAssertEqual(vm.surfEscapeStatus, .idle)
    }

    // MARK: - T14: last-used duration persistence

    func testSelectedDurationRestoredFromSettings() throws {
        let settings = SettingsStore(defaults: isolatedDefaults("swell.tests.restore"))
        settings.selectedDuration = 7200

        let vm = try makeVM(calendar: MockCalendarService(), settings: settings)
        XCTAssertEqual(vm.selectedDuration, 7200)
    }

    func testSelectedDurationPersistsOnChange() throws {
        let defaults = isolatedDefaults("swell.tests.persist")
        let settings = SettingsStore(defaults: defaults)

        let vm = try makeVM(calendar: MockCalendarService(), settings: settings)
        vm.selectedDuration = 1800   // triggers didSet → persist

        // A fresh store over the same defaults sees the persisted value.
        XCTAssertEqual(SettingsStore(defaults: defaults).selectedDuration, 1800)
    }

    // MARK: - Helpers

    private func makeVM(calendar: MockCalendarService,
                        title: String = "Underwater Basket Weaving",
                        settings: SettingsStore? = nil) throws -> MenuViewModel {
        let url = Bundle(for: type(of: self)).url(forResource: "spots.fixture", withExtension: "json")!
        return MenuViewModel(
            registry: try SpotRegistry(url: url),
            store: try HistoryStore(inMemory: true),
            calendarService: calendar,
            titleGenerator: StubTitleGenerator(title: title),
            settings: settings ?? SettingsStore(defaults: isolatedDefaults())
        )
    }

    private func isolatedDefaults(_ name: String = "swell.tests.vm") -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func isFailure(_ status: MenuViewModel.SurfEscapeStatus) -> Bool {
        if case .failure = status { return true }
        return false
    }

    /// Polls `condition` on the main actor until true or the timeout elapses.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)   // 10ms
        }
    }
}
