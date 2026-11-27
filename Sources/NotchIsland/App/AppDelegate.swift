import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let settingsWindow = SettingsWindowController()
    private var viewModel: NotchViewModel?
    private var controller: NotchController?
    private var desktopLyrics: DesktopLyricsController?
    private var edgeGlow: EdgeGlowController?
    private var lockScreen: LockScreenController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = NotchViewModel(settings: settings)
        viewModel.openSettings = { [weak self] in self?.showSettings() }
        self.viewModel = viewModel
        controller = NotchController(viewModel: viewModel, settings: settings)
        desktopLyrics = DesktopLyricsController(viewModel: viewModel)
        let glow = EdgeGlowController(viewModel: viewModel)
        edgeGlow = glow
        let lock = LockScreenController(viewModel: viewModel, glow: glow)
        lockScreen = lock
        viewModel.previewLockScreen = { [weak lock] in lock?.preview() }

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
        desktopLyrics?.update()
        edgeGlow?.update()
        lockScreen?.update()
    }

    @objc private func showSettings() {
        guard let viewModel else { return }
        settingsWindow.show(settings: settings, viewModel: viewModel)
    }

    /// Menu bar icon for macOS 10.15, which has no SF Symbols: a small filled capsule.
    private static func capsuleIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 6, width: rect.width - 4, height: 7),
                         xRadius: 3.5, yRadius: 3.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage.symbol("capsule.fill", description: "NotchIsland") ?? Self.capsuleIcon()

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
