import AppKit
import Combine
import SwiftUI

/// Shows lyrics on the desktop: a full-screen window that sits just above the
/// wallpaper, below desktop icons and every app window. It never takes clicks.
@MainActor
final class DesktopLyricsController {
    private let vm: NotchViewModel
    private var window: DesktopWindow?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: NotchViewModel) {
        vm = viewModel
        let settings = viewModel.settings

        Publishers.CombineLatest4(
            settings.$desktopLyricsStyle.map { _ in () },
            settings.$lyricsEnabled.map { _ in () },
            viewModel.nowPlaying.$track.map { _ in () },
            viewModel.lyrics.$lyrics.map { _ in () }
        )
        // @Published fires before the value changes; read the new values on the next pass.
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.update() }
        .store(in: &cancellables)
    }

    func update() {
        let settings = vm.settings
        let shouldShow = settings.lyricsEnabled
            && settings.desktopLyricsStyle != .off
            && vm.nowPlaying.track != nil
            && vm.lyrics.lyrics != nil

        guard shouldShow else {
            window?.orderOut(nil)
            return
        }

        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(screenFrame(), display: true)
        window.orderFrontRegardless()
    }

    private func screenFrame() -> NSRect {
        let frame = vm.geometry.screenFrame
        if frame.width > 0 { return frame }
        return NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? .zero
    }

    private func makeWindow() -> DesktopWindow {
        let window = DesktopWindow(contentRect: screenFrame(),
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: DesktopLyricsView(vm: vm, settings: vm.settings))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }
}

/// Borderless window that may cover the whole screen, menu bar area included.
final class DesktopWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
