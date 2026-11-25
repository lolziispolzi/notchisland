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

/// The widgets the island can show. Each one is a tab when the island is open.
enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case media
    case weather
    case calendar
    case sports
    case drop
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Now Playing"
        case .weather: "Weather"
        case .calendar: "Calendar"
        case .sports: "Sports"
        case .drop: "Drop Zone"
        case .notes: "Notes"
        }
    }

    /// Short label for the customize bar.
    var shortTitle: String {
        switch self {
        case .media: "Music"
        case .weather: "Weather"
        case .calendar: "Calendar"
        case .sports: "Sports"
        case .drop: "Drop"
        case .notes: "Notes"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .weather: "cloud.sun.fill"
        case .calendar: "calendar"
        case .sports: "sportscourt.fill"
        case .drop: "tray.and.arrow.down.fill"
        case .notes: "note.text"
        }
    }
}

enum IslandSize: String, CaseIterable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    var openSize: CGSize {
        switch self {
        case .compact: CGSize(width: 560, height: 190)
        case .regular: CGSize(width: 640, height: 210)
        case .large: CGSize(width: 720, height: 250)
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }

    /// Value for Open-Meteo's `wind_speed_unit` parameter.
    var windUnit: String {
        switch self {
        case .celsius: "kmh"
        case .fahrenheit: "mph"
        }
    }

    var windLabel: String {
        switch self {
        case .celsius: "km/h"
        case .fahrenheit: "mph"
        }
    }

    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

enum DesktopLyricsStyle: String, CaseIterable, Identifiable {
    case off
    /// Cover, title and progress on the left, scrolling lyrics on the right.
    case coverAndLyrics
    /// Big centered lyrics.
    case bigLyrics
    /// One line near the bottom of the screen.
    case bottomLine
    /// Words light up as stars joined into a constellation.
    case stars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .coverAndLyrics: "Cover and lyrics"
        case .bigLyrics: "Big lyrics"
        case .bottomLine: "Bottom line"
        case .stars: "Stars"
        }
    }
}

enum LyricsTextSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.3
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
        static let showLiveActivities = "showLiveActivities"
        static let showBattery = "showBattery"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let displayChoice = "displayChoice"
        static let islandSize = "islandSize"
        static let widgetOrder = "widgetOrder"
        static let hiddenWidgets = "hiddenWidgets"
        static let temperatureUnit = "temperatureUnit"
        static let useCurrentLocation = "useCurrentLocation"
        static let manualLocation = "manualLocation"
        static let sportsLeague = "sportsLeague"
        static let favoriteTeam = "favoriteTeam"
        static let eventHeadsUpMinutes = "eventHeadsUpMinutes"
        static let newEventAlertMinutes = "newEventAlertMinutes"
        static let customDropFolders = "customDropFolders"
        static let removeAfterCopy = "removeAfterCopy"
        static let lyricsEnabled = "lyricsEnabled"
        static let lyricsUnderNotch = "lyricsUnderNotch"
        static let lyricsOffset = "lyricsOffset"
        static let desktopLyricsStyle = "desktopLyricsStyle"
        static let desktopLyricsTint = "desktopLyricsTint"
        static let desktopLyricsSize = "desktopLyricsSize"
        static let lockScreenEnabled = "lockScreenEnabled"
        static let lockScreenLyricsStyle = "lockScreenLyricsStyle"
        static let edgeGlowEnabled = "edgeGlowEnabled"
        static let edgeGlowReactsToAudio = "edgeGlowReactsToAudio"
    }

    private let defaults: UserDefaults

    // MARK: General

    @Published var openOnHover: Bool {
        didSet { defaults.set(openOnHover, forKey: Key.openOnHover) }
    }
    @Published var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }
    @Published var showLiveActivities: Bool {
        didSet { defaults.set(showLiveActivities, forKey: Key.showLiveActivities) }
    }
    @Published var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: Key.showBattery) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published var displayChoice: DisplayChoice {
        didSet { defaults.set(displayChoice.rawValue, forKey: Key.displayChoice) }
    }

    // MARK: Layout

    @Published var islandSize: IslandSize {
        didSet { defaults.set(islandSize.rawValue, forKey: Key.islandSize) }
    }
    @Published var widgetOrder: [WidgetKind] {
        didSet { defaults.set(widgetOrder.map(\.rawValue), forKey: Key.widgetOrder) }
    }
    @Published var hiddenWidgets: Set<WidgetKind> {
        didSet { defaults.set(hiddenWidgets.map(\.rawValue).sorted(), forKey: Key.hiddenWidgets) }
    }

    // MARK: Weather

    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }
    @Published var useCurrentLocation: Bool {
        didSet { defaults.set(useCurrentLocation, forKey: Key.useCurrentLocation) }
    }
    @Published var manualLocation: WeatherLocation? {
        didSet { storeCodable(manualLocation, forKey: Key.manualLocation) }
    }

    // MARK: Sports

    @Published var sportsLeague: SportsLeague {
        didSet { defaults.set(sportsLeague.rawValue, forKey: Key.sportsLeague) }
    }
    @Published var favoriteTeam: SavedTeam? {
        didSet { storeCodable(favoriteTeam, forKey: Key.favoriteTeam) }
    }

    // MARK: Calendar

    /// Minutes before an event to show it next to the notch. 0 turns it off.
    @Published var eventHeadsUpMinutes: Int {
        didSet { defaults.set(eventHeadsUpMinutes, forKey: Key.eventHeadsUpMinutes) }
    }
    /// Alert added to events created from the island. 0 means no alert.
    @Published var newEventAlertMinutes: Int {
        didSet { defaults.set(newEventAlertMinutes, forKey: Key.newEventAlertMinutes) }
    }

    // MARK: Drop zone

    @Published var customDropFolders: [String] {
        didSet { defaults.set(customDropFolders, forKey: Key.customDropFolders) }
    }
    @Published var removeAfterCopy: Bool {
        didSet { defaults.set(removeAfterCopy, forKey: Key.removeAfterCopy) }
    }

    // MARK: Lyrics

    /// Look up lyrics on LRCLIB for the playing song.
    @Published var lyricsEnabled: Bool {
        didSet { defaults.set(lyricsEnabled, forKey: Key.lyricsEnabled) }
    }
    /// Show the line being sung under the closed notch.
    @Published var lyricsUnderNotch: Bool {
        didSet { defaults.set(lyricsUnderNotch, forKey: Key.lyricsUnderNotch) }
    }
    /// Seconds to shift lyrics. Positive shows them earlier.
    @Published var lyricsOffset: Double {
        didSet { defaults.set(lyricsOffset, forKey: Key.lyricsOffset) }
    }
    @Published var desktopLyricsStyle: DesktopLyricsStyle {
        didSet { defaults.set(desktopLyricsStyle.rawValue, forKey: Key.desktopLyricsStyle) }
    }
    /// Fill the desktop with the album's colors behind the lyrics.
    @Published var desktopLyricsTint: Bool {
        didSet { defaults.set(desktopLyricsTint, forKey: Key.desktopLyricsTint) }
    }
    @Published var desktopLyricsSize: LyricsTextSize {
        didSet { defaults.set(desktopLyricsSize.rawValue, forKey: Key.desktopLyricsSize) }
    }

    // MARK: Lock screen and glow

    /// Show the player (and lyrics) on the lock screen. Uses a private macOS API.
    @Published var lockScreenEnabled: Bool {
        didSet { defaults.set(lockScreenEnabled, forKey: Key.lockScreenEnabled) }
    }
    @Published var lockScreenLyricsStyle: DesktopLyricsStyle {
        didSet { defaults.set(lockScreenLyricsStyle.rawValue, forKey: Key.lockScreenLyricsStyle) }
    }
    /// A line of light around the screen edge while music plays.
    @Published var edgeGlowEnabled: Bool {
        didSet { defaults.set(edgeGlowEnabled, forKey: Key.edgeGlowEnabled) }
    }
    /// Pulse with the actual sound. Needs Screen & System Audio Recording permission.
    @Published var edgeGlowReactsToAudio: Bool {
        didSet { defaults.set(edgeGlowReactsToAudio, forKey: Key.edgeGlowReactsToAudio) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.openOnHover: true,
            Key.hoverDelay: 0.1,
            Key.hapticsEnabled: true,
            Key.showLiveActivities: true,
            Key.showBattery: true,
            Key.showMenuBarIcon: true,
            Key.displayChoice: DisplayChoice.notchScreen.rawValue,
            Key.islandSize: IslandSize.compact.rawValue,
            Key.temperatureUnit: TemperatureUnit.localeDefault.rawValue,
            Key.useCurrentLocation: true,
            Key.sportsLeague: SportsLeague.nba.rawValue,
            Key.eventHeadsUpMinutes: 10,
            Key.newEventAlertMinutes: 10,
            Key.removeAfterCopy: false,
            Key.lyricsEnabled: true,
            Key.lyricsUnderNotch: true,
            Key.lyricsOffset: 0.0,
            Key.desktopLyricsStyle: DesktopLyricsStyle.coverAndLyrics.rawValue,
            Key.desktopLyricsTint: true,
            Key.desktopLyricsSize: LyricsTextSize.medium.rawValue,
            Key.lockScreenEnabled: false,
            Key.lockScreenLyricsStyle: DesktopLyricsStyle.stars.rawValue,
            Key.edgeGlowEnabled: false,
            Key.edgeGlowReactsToAudio: false,
        ])

        openOnHover = defaults.bool(forKey: Key.openOnHover)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        showLiveActivities = defaults.bool(forKey: Key.showLiveActivities)
        showBattery = defaults.bool(forKey: Key.showBattery)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        displayChoice = DisplayChoice(rawValue: defaults.string(forKey: Key.displayChoice) ?? "") ?? .notchScreen

        islandSize = IslandSize(rawValue: defaults.string(forKey: Key.islandSize) ?? "") ?? .compact
        widgetOrder = Self.normalizedOrder(defaults.stringArray(forKey: Key.widgetOrder) ?? [])
        hiddenWidgets = Set((defaults.stringArray(forKey: Key.hiddenWidgets) ?? []).compactMap(WidgetKind.init(rawValue:)))

        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Key.temperatureUnit) ?? "") ?? .localeDefault
        useCurrentLocation = defaults.bool(forKey: Key.useCurrentLocation)
        manualLocation = Self.loadCodable(WeatherLocation.self, forKey: Key.manualLocation, from: defaults)

        sportsLeague = SportsLeague(rawValue: defaults.string(forKey: Key.sportsLeague) ?? "") ?? .nba
        favoriteTeam = Self.loadCodable(SavedTeam.self, forKey: Key.favoriteTeam, from: defaults)

        eventHeadsUpMinutes = defaults.integer(forKey: Key.eventHeadsUpMinutes)
        newEventAlertMinutes = defaults.integer(forKey: Key.newEventAlertMinutes)

        customDropFolders = defaults.stringArray(forKey: Key.customDropFolders) ?? []
        removeAfterCopy = defaults.bool(forKey: Key.removeAfterCopy)

        lyricsEnabled = defaults.bool(forKey: Key.lyricsEnabled)
        lyricsUnderNotch = defaults.bool(forKey: Key.lyricsUnderNotch)
        lyricsOffset = defaults.double(forKey: Key.lyricsOffset)
        desktopLyricsStyle = DesktopLyricsStyle(rawValue: defaults.string(forKey: Key.desktopLyricsStyle) ?? "") ?? .coverAndLyrics
        desktopLyricsTint = defaults.bool(forKey: Key.desktopLyricsTint)
        desktopLyricsSize = LyricsTextSize(rawValue: defaults.string(forKey: Key.desktopLyricsSize) ?? "") ?? .medium

        lockScreenEnabled = defaults.bool(forKey: Key.lockScreenEnabled)
        lockScreenLyricsStyle = DesktopLyricsStyle(rawValue: defaults.string(forKey: Key.lockScreenLyricsStyle) ?? "") ?? .stars
        edgeGlowEnabled = defaults.bool(forKey: Key.edgeGlowEnabled)
        edgeGlowReactsToAudio = defaults.bool(forKey: Key.edgeGlowReactsToAudio)

        // Never start with every widget hidden.
        if visibleWidgets.isEmpty { hiddenWidgets = [] }
    }

    // MARK: - Widgets

    var visibleWidgets: [WidgetKind] {
        widgetOrder.filter { !hiddenWidgets.contains($0) }
    }

    func isVisible(_ widget: WidgetKind) -> Bool {
        !hiddenWidgets.contains(widget)
    }

    /// Shows or hides a widget. The last visible widget cannot be hidden.
    func setVisible(_ widget: WidgetKind, _ visible: Bool) {
        if visible {
            hiddenWidgets.remove(widget)
        } else if visibleWidgets.count > 1 {
            hiddenWidgets.insert(widget)
        }
    }

    func move(_ widget: WidgetKind, by offset: Int) {
        widgetOrder = Self.moved(widgetOrder, widget, by: offset)
    }

    nonisolated static func moved(_ order: [WidgetKind], _ widget: WidgetKind, by offset: Int) -> [WidgetKind] {
        guard let index = order.firstIndex(of: widget) else { return order }
        let target = min(max(index + offset, 0), order.count - 1)
        var result = order
        result.remove(at: index)
        result.insert(widget, at: target)
        return result
    }

    /// Turns stored raw values into a full, duplicate-free order. Widgets added in
    /// later versions are appended at the end.
    nonisolated static func normalizedOrder(_ raw: [String]) -> [WidgetKind] {
        var result: [WidgetKind] = []
        for value in raw {
            if let widget = WidgetKind(rawValue: value), !result.contains(widget) {
                result.append(widget)
            }
        }
        for widget in WidgetKind.allCases where !result.contains(widget) {
            result.append(widget)
        }
        return result
    }

    // MARK: - Codable storage

    private func storeCodable<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
