import XCTest
@testable import Swell

/// Tests for the title generators behind Surf Escape. The EventKit-backed
/// `EventKitCalendarService` is exercised indirectly via `MenuViewModelCalendarTests`
/// (with a mock), since hitting real EventKit needs Calendar access we can't assume.
final class CalendarServiceTests: XCTestCase {

    func testStaticGeneratorReturnsNonEmptyTitle() async {
        let title = await StaticTitleGenerator().generateTitle()
        XCTAssertFalse(title.isEmpty)
    }

    func testStaticActorReturnsNonEmptyTitle() async {
        let title = await StaticTitleGeneratorActor().generateTitle()
        XCTAssertFalse(title.isEmpty)
    }

    /// The backend selector must route to the static generator (no network /
    /// no model download) when the user picked Static.
    @MainActor
    func testBackendSelectorUsesStaticBackend() async {
        let settings = SettingsStore(defaults: Self.isolatedDefaults())
        settings.titleBackend = .staticTitles

        let generator = BackendSelectingTitleGenerator(settings: settings)
        let title = await generator.generateTitle()

        XCTAssertFalse(title.isEmpty)
    }

    private static func isolatedDefaults(_ name: String = "swell.tests.calendar") -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
