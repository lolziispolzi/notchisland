import AppKit

/// Entry point. Runs as an accessory app: no Dock icon, no app menu.
@main
@MainActor
enum NotchIslandMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
