import SwiftUI

/// The dropdown root: header, conditions strip, spot rows, footer actions.
struct MenuContentView: View {
    @ObservedObject var vm: MenuViewModel
    let onSampleNow: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Swell", systemImage: "water.waves").font(.system(size: 15, weight: .medium))
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ConditionsStrip(c: vm.conditions).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ForEach(vm.rows) { SpotRow(row: $0) }
            Divider()
            HStack {
                Button { onSampleNow() } label: { Label("Sample now", systemImage: "arrow.clockwise") }
                Spacer()
                Button("Quit") { onQuit() }
            }.padding(.horizontal, 14).padding(.vertical, 9).font(.system(size: 12))
        }
        .frame(width: 340)
        .onAppear { vm.refresh() }
    }
}
