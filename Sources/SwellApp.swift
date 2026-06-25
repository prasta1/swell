import SwiftUI
import ServiceManagement
import CoreLocation

@main
struct SwellApp: App {
    @StateObject private var vm: MenuViewModel
    @StateObject private var firstLaunchManager = FirstLaunchManager()
    @StateObject private var permissionService = SystemPermissionService()
    @StateObject private var camViewer: CamViewerModel
    private let sampler: Sampler
    private let calendarService: EventKitCalendarService
    private let titleGenerator: BackendSelectingTitleGenerator

    init() {
        let registry = try! SpotRegistry.bundled()
        let store = try! HistoryStore()
        let detector = try! YOLODetector()
        let calendarService = EventKitCalendarService()
        let titleGenerator = BackendSelectingTitleGenerator()
        self.calendarService = calendarService
        self.titleGenerator = titleGenerator
        let vm = MenuViewModel(registry: registry, store: store, calendarService: calendarService, titleGenerator: titleGenerator)
        _vm = StateObject(wrappedValue: vm)
        _camViewer = StateObject(wrappedValue: CamViewerModel(spots: registry.spots, detector: detector))
        sampler = Sampler(registry: registry, store: store, detector: detector,
                          conditions: ConditionsService())
        #if !DEBUG
        try? SMAppService.mainApp.register()   // launch at login
        #endif
    }

    var body: some Scene {
        MenuBarExtra("Swell", systemImage: "water.waves") {
            MenuBarContent(vm: vm, sampler: sampler, firstLaunchManager: firstLaunchManager,
                           calendarService: calendarService, titleGenerator: titleGenerator,
                           camViewer: camViewer)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Welcome to Swell", id: "first-launch") {
            OnboardingWindow(permissionService: permissionService, firstLaunchManager: firstLaunchManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 520)

        Window("Surf Cams", id: "cam-viewer") {
            CamViewerView(model: camViewer)
        }
        .defaultSize(width: 820, height: 560)
    }
}

/// Wrapper view that holds `openWindow` so it can be called imperatively from `.task`.
private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var vm: MenuViewModel
    let sampler: Sampler
    @ObservedObject var firstLaunchManager: FirstLaunchManager
    let calendarService: CalendarService
    let titleGenerator: MeetingTitleGenerator
    let camViewer: CamViewerModel

    var body: some View {
        MenuContentView(
            vm: vm,
            calendarService: calendarService,
            titleGenerator: titleGenerator,
            onViewCam: { spotID in
                camViewer.selectedSpotID = spotID
                openWindow(id: "cam-viewer")
                NSApp.activate()
            },
            onSampleNow: {
                Task {
                    await sampler.tick()
                    vm.conditions = sampler.conditionsSnapshot
                    vm.refresh()
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )
        .task {
            sampler.start()
            vm.conditions = sampler.conditionsSnapshot
            vm.refresh()

            if firstLaunchManager.isFirstLaunch {
                firstLaunchManager.markLaunched()
                openWindow(id: "first-launch")
            }
        }
    }
}

/// Thin wrapper that supplies `dismiss` to the onboarding view when the user taps Continue.
private struct OnboardingWindow: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var permissionService: SystemPermissionService
    @ObservedObject var firstLaunchManager: FirstLaunchManager

    var body: some View {
        FirstLaunchView(
            permissionService: permissionService,
            firstLaunchManager: firstLaunchManager,
            onComplete: {
                firstLaunchManager.markOnboardingCompleted()
                dismiss()
            }
        )
    }
}
