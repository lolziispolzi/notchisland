import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notchController = NotchController()
        setUpStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        notchController?.reposition()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit NotchIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
