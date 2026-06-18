import SwiftUI

/// Duration options for the surf escape.
private struct SurfDuration: Identifiable, Hashable {
    let id: String
    let label: String
    let interval: TimeInterval
    var isCustom: Bool { id == "custom" }

    static let presets: [SurfDuration] = [
        SurfDuration(id: "30m", label: "30m", interval: 1800),
        SurfDuration(id: "1h", label: "1h", interval: 3600),
        SurfDuration(id: "2h", label: "2h", interval: 7200),
        SurfDuration(id: "custom", label: "Custom…", interval: 0),
    ]
}

/// Popover for custom duration selection.
private struct CustomDurationPopover: View {
    @Binding var selection: TimeInterval?
    @Environment(\.dismiss) private var dismiss

    @State private var hours: Int = 1
    @State private var minutes: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Custom Duration")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 12) {
                Stepper("Hours: \(hours)", value: $hours, in: 0...4)
                    .labelsHidden()
                    .frame(width: 120)
                Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59, step: 15)
                    .labelsHidden()
                    .frame(width: 140)
            }
            .padding(.horizontal, 16)

            Button("Set") {
                let totalSeconds = TimeInterval(hours * 3600 + minutes * 60)
                if totalSeconds > 0 && totalSeconds <= 14400 {  // max 4 hours
                    selection = totalSeconds
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(hours == 0 && minutes == 0)
        }
        .padding(.vertical, 16)
        .frame(width: 280)
        .onAppear {
            if let sel = selection {
                hours = Int(sel) / 3600
                minutes = (Int(sel) % 3600) / 60
            }
        }
    }
}

/// The dropdown root: header, conditions strip, spot rows, footer actions.
struct MenuContentView: View {
    @ObservedObject var vm: MenuViewModel
    let calendarService: CalendarService
    let titleGenerator: MeetingTitleGenerator
    let onViewCam: (String) -> Void
    let onSampleNow: () -> Void
    let onQuit: () -> Void

    @State private var showCustomDuration = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Swell", systemImage: "water.waves").font(.system(size: 15, weight: .medium))
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView(calendarService: calendarService, titleGenerator: titleGenerator)
                }
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ConditionsStrip(c: vm.conditions).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ForEach(vm.rows) { SpotRow(row: $0, onViewCam: onViewCam) }
            Divider()
            SurfEscapeFooter(vm: vm, showCustomDuration: $showCustomDuration)
            Divider()
            HStack {
                Button { onSampleNow() } label: { Label("Sample now", systemImage: "arrow.clockwise") }
                Spacer()
                Button("Quit") { onQuit() }
            }.padding(.horizontal, 14).padding(.vertical, 9).font(.system(size: 12))
        }
        .frame(width: 340)
        .popover(isPresented: $showCustomDuration) {
            CustomDurationPopover(selection: $vm.selectedDuration)
        }
        .onAppear { vm.refresh() }
    }
}

/// Footer with duration pills and Go Surf button.
private struct SurfEscapeFooter: View {
    @ObservedObject var vm: MenuViewModel
    @Binding var showCustomDuration: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            // Status row — only present when there's something to show, so the VStack
            // doesn't reserve an empty spacing slot above the pills when idle.
            if showsStatus {
                statusRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Duration pills
            HStack(spacing: 8) {
                ForEach(SurfDuration.presets) { duration in
                    Button {
                        if duration.isCustom {
                            showCustomDuration = true
                        } else {
                            vm.selectedDuration = duration.interval
                        }
                    } label: {
                        Text(duration.label)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                vm.selectedDuration == duration.interval && !duration.isCustom
                                ? Color.accentColor
                                : Color.secondary.opacity(0.15)
                            )
                            .foregroundStyle(
                                vm.selectedDuration == duration.interval && !duration.isCustom
                                ? .white
                                : .primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Go Surf — full-width primary action (own row so the label never truncates)
            Button {
                vm.goSurf()
            } label: {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "figure.surfing")
                    }
                    Text("Go Surf")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.selectedDuration == nil || isLoading)
            .help("Create a calendar event to go surf")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: vm.surfEscapeStatus)
    }

    /// True only for terminal states that render a status row.
    private var showsStatus: Bool {
        switch vm.surfEscapeStatus {
        case .success, .permissionDenied, .failure: return true
        default: return false
        }
    }

    /// The success/denied/error row shown above the pills. Padding and transition
    /// are applied by the caller.
    @ViewBuilder private var statusRow: some View {
        switch vm.surfEscapeStatus {
        case .success(let title, let duration):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("🌊 Blocked \(durationLabel(duration)) as \"\(title)\"")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
        case .permissionDenied:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Calendar access denied.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Open Settings") { openCalendarSettings() }
                    .font(.system(size: 11))
                    .buttonStyle(.link)
                Spacer()
            }
        case .failure(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        default:
            EmptyView()
        }
    }

    private var isLoading: Bool {
        if case .requestingPermission = vm.surfEscapeStatus { return true }
        if case .generatingTitle = vm.surfEscapeStatus { return true }
        if case .creatingEvent = vm.surfEscapeStatus { return true }
        return false
    }

    /// Compact label for the blocked duration, e.g. 5400s → "1h 30m", 3600s → "1h".
    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    /// Opens System Settings → Privacy & Security → Calendars so the user can grant access.
    private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            openURL(url)
        }
    }
}
