import AppKit
import Combine

enum NotchTab: String, CaseIterable {
    case home
    case shelf

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.fill"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        }
    }
}

/// What the island shows while closed.
enum ClosedActivity: Equatable {
    case none
    case nowPlaying
    case charging

    /// Extra width added on each side of the notch.
    var sideWidth: CGFloat {
        switch self {
        case .none: 0
        case .nowPlaying: 40
        case .charging: 64
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var geometry: NotchGeometry
    @Published var tab: NotchTab = .home
    @Published var isDropTargeted = false
    @Published private(set) var transientActivity: ClosedActivity?

    let settings: AppSettings
    let nowPlaying = NowPlayingService()
    let battery = BatteryService()
    let shelf = ShelfStore()

    /// Set by the app delegate.
    var openSettings: () -> Void = {}

    private var transientWork: DispatchWorkItem?

    init(settings: AppSettings) {
        self.settings = settings
        self.geometry = NotchGeometry.current(for: settings.displayChoice) ?? .placeholder

        battery.onPluggedIn = { [weak self] in
            guard let self, self.settings.showLiveActivities, self.settings.showBattery else { return }
            self.flash(.charging)
        }
    }

    var closedActivity: ClosedActivity {
        if let transientActivity { return transientActivity }
        if settings.showLiveActivities, settings.showNowPlaying,
           nowPlaying.isPlaying, nowPlaying.track != nil {
            return .nowPlaying
        }
        return .none
    }

    var closedExtraWidth: CGFloat { closedActivity.sideWidth * 2 }

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
        battery.refresh()
        nowPlaying.refreshPosition()
        if tab == .shelf, !settings.showShelf { tab = .home }
    }
}
