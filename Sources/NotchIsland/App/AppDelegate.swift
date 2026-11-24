import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let settingsWindow = SettingsWindowController()
    private var viewModel: NotchViewModel?
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = NotchViewModel(settings: settings)
        viewModel.openSettings = { [weak self] in self?.showSettings() }
        self.viewModel = viewModel
        controller = NotchController(viewModel: viewModel, settings: settings)

        setUpStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        controller?.reposition()
    }

    @objc private func showSettings() {
        settingsWindow.show(settings: settings)
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchIsland",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        item.isVisible = settings.showMenuBarIcon
        statusItem = item

        settings.$showMenuBarIcon
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)
    }
}
