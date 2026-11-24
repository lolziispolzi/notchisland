import Foundation
import Combine

enum DisplayChoice: String, CaseIterable, Identifiable {
    case notchScreen
    case primaryScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notchScreen: "Built-in display (notch)"
        case .primaryScreen: "Primary display"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let openOnHover = "openOnHover"
        static let hoverDelay = "hoverDelay"
        static let hapticsEnabled = "hapticsEnabled"
        static let showNowPlaying = "showNowPlaying"
        static let showLiveActivities = "showLiveActivities"
        static let showBattery = "showBattery"
        static let showShelf = "showShelf"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let displayChoice = "displayChoice"
    }

    private let defaults: UserDefaults

    @Published var openOnHover: Bool {
        didSet { defaults.set(openOnHover, forKey: Key.openOnHover) }
    }
    @Published var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }
    @Published var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: Key.showNowPlaying) }
    }
    @Published var showLiveActivities: Bool {
        didSet { defaults.set(showLiveActivities, forKey: Key.showLiveActivities) }
    }
    @Published var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: Key.showBattery) }
    }
    @Published var showShelf: Bool {
        didSet { defaults.set(showShelf, forKey: Key.showShelf) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published var displayChoice: DisplayChoice {
        didSet { defaults.set(displayChoice.rawValue, forKey: Key.displayChoice) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.openOnHover: true,
            Key.hoverDelay: 0.1,
            Key.hapticsEnabled: true,
            Key.showNowPlaying: true,
            Key.showLiveActivities: true,
            Key.showBattery: true,
            Key.showShelf: true,
            Key.showMenuBarIcon: true,
            Key.displayChoice: DisplayChoice.notchScreen.rawValue,
        ])
        openOnHover = defaults.bool(forKey: Key.openOnHover)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        showNowPlaying = defaults.bool(forKey: Key.showNowPlaying)
        showLiveActivities = defaults.bool(forKey: Key.showLiveActivities)
        showBattery = defaults.bool(forKey: Key.showBattery)
        showShelf = defaults.bool(forKey: Key.showShelf)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        displayChoice = DisplayChoice(rawValue: defaults.string(forKey: Key.displayChoice) ?? "") ?? .notchScreen
    }
}
