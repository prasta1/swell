import Foundation

/// Manages first-launch detection and onboarding state.
@MainActor
final class FirstLaunchManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private let hasLaunchedKey = "hasLaunchedBefore"
    private let onboardingCompletedKey = "onboardingCompleted"

    /// Whether this is the first launch of the app.
    @Published var isFirstLaunch: Bool = false

    /// Whether the onboarding flow has been completed.
    @Published var onboardingCompleted: Bool = false

    /// Initialize and check first-launch status.
    init() {
        let hasLaunched = defaults.bool(forKey: hasLaunchedKey)
        isFirstLaunch = !hasLaunched
        onboardingCompleted = defaults.bool(forKey: onboardingCompletedKey)
    }

    /// Mark that the app has launched (call once on first launch).
    func markLaunched() {
        defaults.set(true, forKey: hasLaunchedKey)
        isFirstLaunch = false
    }

    /// Mark that onboarding has been completed.
    func markOnboardingCompleted() {
        defaults.set(true, forKey: onboardingCompletedKey)
        onboardingCompleted = true
    }

    /// Reset first-launch state (for testing/debugging).
    func reset() {
        defaults.removeObject(forKey: hasLaunchedKey)
        defaults.removeObject(forKey: onboardingCompletedKey)
        isFirstLaunch = true
        onboardingCompleted = false
    }
}

/// Preview-only first launch manager.
@MainActor
final class PreviewFirstLaunchManager: ObservableObject {
    @Published var isFirstLaunch: Bool = true
    @Published var onboardingCompleted: Bool = false

    func markLaunched() { isFirstLaunch = false }
    func markOnboardingCompleted() { onboardingCompleted = true }
    func reset() { isFirstLaunch = true; onboardingCompleted = false }
}