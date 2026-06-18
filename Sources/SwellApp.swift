import SwiftUI
import ServiceManagement

@main
struct SwellApp: App {
    @StateObject private var vm: MenuViewModel
    private let sampler: Sampler

    init() {
        let registry = try! SpotRegistry.bundled()
        let store = try! HistoryStore()
        let detector = try! YOLODetector()
        let vm = MenuViewModel(registry: registry, store: store)
        _vm = StateObject(wrappedValue: vm)
        sampler = Sampler(registry: registry, store: store, detector: detector,
                          conditions: ConditionsService())
        try? SMAppService.mainApp.register()   // launch at login
    }

    var body: some Scene {
        MenuBarExtra("Swell", systemImage: "water.waves") {
            MenuContentView(
                vm: vm,
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
            }
        }
        .menuBarExtraStyle(.window)
    }
}
