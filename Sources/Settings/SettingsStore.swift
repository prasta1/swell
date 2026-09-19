import Foundation

/// Persisted user settings for Swell.
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    // Keys
    private enum Key: String {
        case selectedDuration
        case titleBackend
        case defaultCalendarID
        case favoriteSpotIDs     // stored as [String]; surfaced as Set<String>
        case showFavoritesOnly
    }

    /// Selected LLM backend for meeting titles.
    enum TitleBackend: String, CaseIterable, Identifiable {
        case staticTitles = "static"
        case mlx = "mlx"
        // case remote = "remote" // future

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .staticTitles: return "Static (instant, no download)"
            case .mlx: return "MLX Local LLM (downloads ~100MB on first use)"
            }
        }
    }

    var selectedDuration: TimeInterval {
        get { defaults.double(forKey: Key.selectedDuration.rawValue) > 0 ? defaults.double(forKey: Key.selectedDuration.rawValue) : 3600 }
        set { defaults.set(newValue, forKey: Key.selectedDuration.rawValue) }
    }

    var titleBackend: TitleBackend {
        get {
            if let raw = defaults.string(forKey: Key.titleBackend.rawValue),
               let backend = TitleBackend(rawValue: raw) {
                return backend
            }
            return .staticTitles
        }
        set { defaults.set(newValue.rawValue, forKey: Key.titleBackend.rawValue) }
    }

    var defaultCalendarID: String? {
        get { defaults.string(forKey: Key.defaultCalendarID.rawValue) }
        set { defaults.set(newValue, forKey: Key.defaultCalendarID.rawValue) }
    }

    /// IDs of spots the user has starred. UserDefaults can't store Set, so
    /// the backing type is [String]; this property bridges to Set<String>.
    var favoriteSpotIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.favoriteSpotIDs.rawValue) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.favoriteSpotIDs.rawValue) }
    }

    /// When true the menu collapses to favorited spots only.
    var showFavoritesOnly: Bool {
        get { defaults.bool(forKey: Key.showFavoritesOnly.rawValue) }
        set { defaults.set(newValue, forKey: Key.showFavoritesOnly.rawValue) }
    }

    func isFavorite(_ spotID: String) -> Bool { favoriteSpotIDs.contains(spotID) }

    func toggleFavorite(_ spotID: String) {
        var ids = favoriteSpotIDs
        if ids.contains(spotID) { ids.remove(spotID) } else { ids.insert(spotID) }
        favoriteSpotIDs = ids
    }

    /// - Parameter defaults: backing store; inject a throwaway instance in tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
