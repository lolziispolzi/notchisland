import Foundation
import ServiceManagement

/// Starts NotchIsland when you log in. Uses SMAppService on macOS 13 and newer, and a
/// LaunchAgent in ~/Library/LaunchAgents on older systems. Only works from the bundled .app.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var isEnabled = LaunchAtLogin.currentlyEnabled()
    @Published private(set) var errorMessage: String?

    private static let label = "io.github.notchisland.launcher"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func set(_ enabled: Bool) {
        do {
            if #available(macOS 13, *) {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } else {
                try Self.setLaunchAgent(enabled)
            }
            errorMessage = nil
        } catch {
            errorMessage = Bundle.main.bundleIdentifier == nil
                ? "Launch at login only works from NotchIsland.app, not from swift run."
                : error.localizedDescription
        }
        isEnabled = Self.currentlyEnabled()
    }

    private static func currentlyEnabled() -> Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Writes or removes a LaunchAgent that opens the app at login.
    private static func setLaunchAgent(_ enabled: Bool) throws {
        let fileManager = FileManager.default
        guard enabled else {
            if fileManager.fileExists(atPath: agentURL.path) {
                try fileManager.removeItem(at: agentURL)
            }
            return
        }
        guard Bundle.main.bundleIdentifier != nil else {
            throw CocoaError(.featureUnsupported)
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try fileManager.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: agentURL, options: .atomic)
    }
}
