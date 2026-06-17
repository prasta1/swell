import SwiftUI

@main
struct SwellApp: App {
    var body: some Scene {
        MenuBarExtra("Swell", systemImage: "water.waves") {
            Text("Swell starting…")
        }
        .menuBarExtraStyle(.window)
    }
}
