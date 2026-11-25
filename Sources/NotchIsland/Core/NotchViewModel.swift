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
    @Published private(set) var transientActivity: ClosedActivity?

    let settings: AppSettings
    let nowPlaying = NowPlayingService()
    let battery = BatteryService()
    let shelf: ShelfStore
    let weather: WeatherService
    let sports: SportsService
    let calendar: CalendarService
    let notes = NotesStore()

    /// Set by the app delegate.
    var openSettings: () -> Void = {}

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

    private func ensureVisibleTab() {
        if !settings.isVisible(tab) {
            tab = settings.visibleWidgets.first ?? .media
        }
    }
}
