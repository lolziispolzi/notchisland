import Foundation
import ServiceManagement

/// Wraps SMAppService. Only works when running from the bundled .app.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = Bundle.main.bundleIdentifier == nil
                ? "Launch at login only works from NotchIsland.app, not from swift run."
                : error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
