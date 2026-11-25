import AppKit

/// Entry point. Runs as an accessory app: no Dock icon, no app menu.
@main
@MainActor
enum NotchIslandMain {
    /// NSApplication holds its delegate weakly, so keep a strong reference here.
    /// A local variable is not enough: in release builds Swift may free it before
    /// `run()` starts, and then `applicationDidFinishLaunching` never fires.
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
