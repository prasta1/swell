import SwiftUI

/// The first-launch onboarding view that requests calendar and location permissions.
struct FirstLaunchView: View {
    @ObservedObject var permissionService: SystemPermissionService
    @ObservedObject var firstLaunchManager: FirstLaunchManager
    let onComplete: () -> Void

    @State private var calendarGranted: Bool = false
    @State private var locationGranted: Bool = false
    @State private var isRequesting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // App icon / branding
            Image(systemName: "water.waves")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .padding(.top, 20)

            // Title
            VStack(spacing: 8) {
                Text("Welcome to Swell")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Let's get you set up to catch the perfect session.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "calendar.badge.plus",
                    title: "Calendar Access",
                    description: "Create calendar events to block out surf time. Swell will add \"Go Surf\" events so your schedule stays clear.",
                    isGranted: calendarGranted,
                    isRequesting: isRequesting
                ) {
                    Task { await requestCalendar() }
                }

                PermissionCard(
                    icon: "location.fill",
                    title: "Location Access",
                    description: "Show nearby surf spots and conditions. Swell uses your location to find the best breaks near you.",
                    isGranted: locationGranted,
                    isRequesting: isRequesting
                ) {
                    Task { await requestLocation() }
                }
            }
            .padding(.horizontal, 24)

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Continue button
            Button {
                onComplete()
            } label: {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .disabled(isRequesting)
        }
        .frame(width: 420, height: 520)
        .onAppear {
            // Check current status
            calendarGranted = permissionService.hasCalendarAccess
            locationGranted = permissionService.hasLocationAccess
        }
    }

    private func requestCalendar() async {
        isRequesting = true
        errorMessage = nil
        let granted = await permissionService.requestCalendarAccess()
        calendarGranted = granted
        isRequesting = false
        if !granted {
            errorMessage = "Calendar access was denied. You can enable it later in System Settings → Privacy & Security → Calendars."
        }
    }

    private func requestLocation() async {
        isRequesting = true
        errorMessage = nil
        let granted = await permissionService.requestLocationAccess()
        locationGranted = granted
        isRequesting = false
        if !granted {
            errorMessage = "Location access was denied. You can enable it later in System Settings → Privacy & Security → Location Services."
        }
    }
}

/// Individual permission card component.
private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isRequesting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .accentColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Button or status
            if isGranted {
                Text("Granted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
            } else if isRequesting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}