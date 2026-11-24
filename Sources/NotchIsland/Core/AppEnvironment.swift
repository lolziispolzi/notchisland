import Foundation

enum AppEnvironment {
    /// True when running from NotchIsland.app. False under `swift run`, where there is
    /// no Info.plist, so macOS cannot show privacy prompts for location or calendars.
    static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }
}

/// Loading state shared by network-backed widgets.
enum LoadState: Equatable {
    case idle
    case loading
    case failed(String)

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
