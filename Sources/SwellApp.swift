import SwiftUI
import ServiceManagement

// TEMPORARY instrumentation for the unresponsive-menubar investigation.
// Appends to a file we can read directly (no unified-log visibility issues).
private func swellInstrument(_ msg: String) {
    let line = "\(Date().timeIntervalSince1970) \(msg)\n"
    let path = "/tmp/swell_inst.log"
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    }
}

private func logMenuWindow(_ tag: String) {
    let screen = NSScreen.main?.frame ?? .zero
    let win = NSApplication.shared.windows.first { $0.className.contains("MenuBarExtra") }
    if let w = win {
        let offTop = w.frame.maxY > screen.maxY
        swellInstrument("\(tag) origin=\(Int(w.frame.minX)),\(Int(w.frame.minY)) size=\(Int(w.frame.width))x\(Int(w.frame.height)) maxY=\(Int(w.frame.maxY)) screenH=\(Int(screen.height)) offTop=\(offTop) visible=\(w.isVisible)")
    } else {
        swellInstrument("\(tag) menuwin: none screenH=\(Int(screen.height))")
    }
}

@main
struct SwellApp: App {
    @StateObject private var vm: MenuViewModel
    private let sampler: Sampler

    init() {
        let registry = try! SpotRegistry.bundled()
        let store = try! HistoryStore()
        let detector = try! YOLODetector()
        let calendarService = EventKitCalendarService()
        let titleGenerator = StaticTitleGeneratorActor()
        let vm = MenuViewModel(registry: registry, store: store, calendarService: calendarService, titleGenerator: titleGenerator)
        _vm = StateObject(wrappedValue: vm)
        sampler = Sampler(registry: registry, store: store, detector: detector,
                          conditions: ConditionsService())
        try? SMAppService.mainApp.register()   // launch at login
        swellInstrument("init")
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
            .onAppear { swellInstrument("onAppear") }
            .task {
                swellInstrument("task")
                logMenuWindow("immediate")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { logMenuWindow("after1s") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { logMenuWindow("after3s") }
                sampler.start()
                vm.conditions = sampler.conditionsSnapshot
                vm.refresh()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
