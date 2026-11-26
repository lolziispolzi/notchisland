import AppKit
import Combine

/// What the island shows while closed, in priority order (see `closedActivity`).
enum ClosedActivity: Equatable {
    case none
    case charging
    case liveScore
    case upcomingEvent
    case nowPlaying

    /// Extra width added on each side of the notch.
    var sideWidth: CGFloat {
        switch self {
        case .none: 0
        case .nowPlaying: 40
        case .charging: 64
        case .liveScore: 70
        case .upcomingEvent: 84
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var geometry: NotchGeometry
    @Published var tab: WidgetKind
    @Published var isDropTargeted = false
    /// The customize bar is showing.
    @Published var isEditing = false
    /// A text field in the island needs the keyboard. Keeps the island open.
    @Published var wantsKeyboard = false
    /// The Music tab shows lyrics instead of the full player.
    @Published var mediaShowsLyrics = false
    /// What the lock screen shows; clicking the cover steps through the modes.
    @Published var lockScreenMode: LockScreenMode = .compact
    /// What the lock-screen code last saw, shown in Settings to help find problems.
    @Published var lockScreenStatus = LockScreenStatus()

    @Published private(set) var transientActivity: ClosedActivity?

    let settings: AppSettings
    let nowPlaying = NowPlayingService()
    let battery = BatteryService()
    let shelf: ShelfStore
    let weather: WeatherService
    let sports: SportsService
    let calendar: CalendarService
    let notes = NotesStore()
    let lyrics: LyricsService
    /// Not forwarded to `objectWillChange`: it updates 30 times a second and only the glow reads it.
    let audio = AudioLevelMonitor()
    /// Not forwarded either: only the Settings window shows it.
    let wallpapers = WallpaperLibrary()

    /// Set by the app delegate.
    var openSettings: () -> Void = {}
    /// Set by the app delegate: shows the lock-screen layout on the desktop for a moment.
    var previewLockScreen: () -> Void = {}

    /// Header button frames in island coordinates (top-left origin), reported by
    /// `HeaderBar`. The controller hit-tests clicks against them.
    var headerTargets: [String: CGRect] = [:]

    private var transientWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        geometry = NotchGeometry.current(for: settings.displayChoice) ?? .placeholder
        tab = settings.visibleWidgets.first ?? .media
        shelf = ShelfStore(settings: settings)
        weather = WeatherService(settings: settings)
        sports = SportsService(settings: settings)
        calendar = CalendarService(settings: settings)
        lyrics = LyricsService(settings: settings, nowPlaying: nowPlaying)

        battery.onPluggedIn = { [weak self] in
            guard let self, self.settings.showLiveActivities, self.settings.showBattery else { return }
            self.flash(.charging)
        }

        // Re-render the island when any service changes.
        let children: [AnyPublisher<Void, Never>] = [
            settings.objectWillChange.eraseToAnyPublisher(),
            nowPlaying.objectWillChange.eraseToAnyPublisher(),
            battery.objectWillChange.eraseToAnyPublisher(),
            shelf.objectWillChange.eraseToAnyPublisher(),
            weather.objectWillChange.eraseToAnyPublisher(),
            sports.objectWillChange.eraseToAnyPublisher(),
            calendar.objectWillChange.eraseToAnyPublisher(),
            notes.objectWillChange.eraseToAnyPublisher(),
            lyrics.objectWillChange.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(children)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // If the selected tab gets hidden, fall back to the first visible one.
        settings.$hiddenWidgets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.ensureVisibleTab() }
            .store(in: &cancellables)
    }

    var closedActivity: ClosedActivity {
        if let transientActivity { return transientActivity }
        guard settings.showLiveActivities else { return .none }
        if settings.isVisible(.sports), sports.snapshot?.featured?.state == .live {
            return .liveScore
        }
        if settings.isVisible(.calendar), calendar.headsUp != nil {
            return .upcomingEvent
        }
        if settings.isVisible(.media), nowPlaying.isPlaying, nowPlaying.track != nil {
            return .nowPlaying
        }
        return .none
    }

    var closedExtraWidth: CGFloat { closedActivity.sideWidth * 2 }

    /// While music plays, the closed island grows a row under the notch with the sung line.
    var showsClosedLyrics: Bool {
        closedActivity == .nowPlaying
            && settings.lyricsEnabled
            && settings.lyricsUnderNotch
            && lyrics.lyrics?.isSynced == true
    }

    static let closedLyricsHeight: CGFloat = 24

    /// Size of the closed island, including any live activity.
    var closedSize: CGSize {
        let notch = geometry.notchRect.size
        var size = CGSize(width: notch.width + closedExtraWidth, height: notch.height)
        if showsClosedLyrics {
            size.width = max(size.width, notch.width + 220)
            size.height += Self.closedLyricsHeight
        }
        return size
    }

    /// Current size of the open island.
    var openSize: CGSize {
        var size = settings.islandSize.openSize
        if isEditing { size.height += NotchGeometry.editBarHeight }
        return size
    }

    /// Shows a closed activity for a few seconds, e.g. "Charging".
    func flash(_ activity: ClosedActivity, duration: TimeInterval = 3) {
        transientWork?.cancel()
        transientActivity = activity
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.transientActivity = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Refreshes data that is only read while open.
    func willOpen() {
        ensureVisibleTab()
        battery.refresh()
        shelf.refreshDestinations()
        if settings.isVisible(.media) {
            nowPlaying.refreshPosition()
            nowPlaying.refreshModes()
        }
        if settings.isVisible(.weather) { weather.refreshIfStale() }
        if settings.isVisible(.sports) { sports.refreshIfStale() }
    }

    func didClose() {
        isEditing = false
        wantsKeyboard = false
        isDropTargeted = false
    }

    // MARK: - Header buttons

    nonisolated static func headerAction(at point: CGPoint, in targets: [String: CGRect]) -> String? {
        targets.first { $0.value.insetBy(dx: -2, dy: -3).contains(point) }?.key
    }

    /// Actions: "tab.<widget>", "customize", "settings".
    func performHeaderAction(_ action: String) {
        switch action {
        case "customize":
            isEditing.toggle()
        case "settings":
            openSettings()
        default:
            if action.hasPrefix("tab."), let widget = WidgetKind(rawValue: String(action.dropFirst(4))) {
                tab = widget
            }
        }
    }

    private func ensureVisibleTab() {
        if !settings.isVisible(tab) {
            tab = settings.visibleWidgets.first ?? .media
        }
    }
}
