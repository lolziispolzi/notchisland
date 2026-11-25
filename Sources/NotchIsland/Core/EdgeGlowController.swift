import AppKit
import Combine
import SwiftUI

/// Shows the edge glow above everything while music plays, and starts audio
/// metering only when the glow is visible and set to react to sound.
@MainActor
final class EdgeGlowController {
    private let vm: NotchViewModel
    private var window: DesktopWindow?
    private var cancellables = Set<AnyCancellable>()
    /// Set by the lock screen controller, which draws its own glow.
    var isLocked = false {
        didSet { update() }
    }

    init(viewModel: NotchViewModel) {
        vm = viewModel
        let settings = viewModel.settings

        Publishers.CombineLatest4(
            settings.$edgeGlowEnabled.map { _ in () },
            settings.$edgeGlowReactsToAudio.map { _ in () },
            viewModel.nowPlaying.$isPlaying.map { _ in () },
            settings.$lockScreenEnabled.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.update() }
        .store(in: &cancellables)
    }

    func update() {
        let settings = vm.settings
        let playing = vm.nowPlaying.isPlaying
        let showOnDesktop = settings.edgeGlowEnabled && playing && !isLocked
        let showOnLockScreen = settings.edgeGlowEnabled && playing && isLocked && settings.lockScreenEnabled

        if showOnDesktop {
            let window = self.window ?? makeWindow()
            self.window = window
            window.setFrame(vm.geometry.screenFrame, display: true)
            window.orderFrontRegardless()
        } else {
            window?.orderOut(nil)
        }

        vm.audio.use("glow", settings.edgeGlowReactsToAudio && (showOnDesktop || showOnLockScreen))
    }

    private func makeWindow() -> DesktopWindow {
        let window = DesktopWindow(contentRect: vm.geometry.screenFrame,
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
        // Above app windows and the menu bar, never taking clicks.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: EdgeGlowView(vm: vm, settings: vm.settings, audio: vm.audio))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }
}
