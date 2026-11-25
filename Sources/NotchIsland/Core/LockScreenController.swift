import AppKit
import Combine
import SwiftUI

/// While the screen is locked and music plays, shows a glass player card and the
/// lyrics above the lock screen. Off unless turned on in Settings, because it relies
/// on a private macOS API (see `LockScreenSpace`).
@MainActor
final class LockScreenController {
    private let vm: NotchViewModel
    private let glow: EdgeGlowController
    private var playerWindow: DesktopWindow?
    private var lyricsWindow: DesktopWindow?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private(set) var isLocked = false

    static let playerSize = CGSize(width: 340, height: 150)

    /// False when the private API is missing on this macOS version.
    static var isSupported: Bool { LockScreenSpace.shared != nil }

    init(viewModel: NotchViewModel, glow: EdgeGlowController) {
        vm = viewModel
        self.glow = glow

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setLocked(true) }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setLocked(false) }
        })

        let settings = viewModel.settings
        Publishers.CombineLatest4(
            settings.$lockScreenEnabled.map { _ in () },
            settings.$lockScreenLyricsStyle.map { _ in () },
            viewModel.nowPlaying.$track.map { _ in () },
            viewModel.lyrics.$lyrics.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.update() }
        .store(in: &cancellables)
    }

    private func setLocked(_ locked: Bool) {
        isLocked = locked
        glow.isLocked = locked
        update()
    }

    func update() {
        let settings = vm.settings
        guard isLocked, settings.lockScreenEnabled, vm.nowPlaying.track != nil,
              let space = LockScreenSpace.shared
        else {
            playerWindow?.orderOut(nil)
            lyricsWindow?.orderOut(nil)
            return
        }

        let screen = vm.geometry.screenFrame

        // Lyrics and glow: full screen, click-through.
        let wantsLyrics = settings.lyricsEnabled && settings.lockScreenLyricsStyle != .off && vm.lyrics.lyrics != nil
        let wantsGlow = settings.edgeGlowEnabled && vm.nowPlaying.isPlaying
        if wantsLyrics || wantsGlow {
            let window = lyricsWindow ?? makeWindow(
                frame: screen,
                clickThrough: true,
                content: LockScreenLyricsView(vm: vm, settings: settings)
            )
            lyricsWindow = window
            window.setFrame(screen, display: true)
            window.orderFrontRegardless()
            space.add(window)
        } else {
            lyricsWindow?.orderOut(nil)
        }

        // Player card: lower middle of the screen, clickable.
        let size = Self.playerSize
        let frame = NSRect(x: screen.midX - size.width / 2,
                           y: screen.minY + screen.height * 0.3,
                           width: size.width,
                           height: size.height)
        let player = playerWindow ?? makeWindow(
            frame: frame,
            clickThrough: false,
            content: LockScreenPlayerCard(nowPlaying: vm.nowPlaying)
        )
        playerWindow = player
        player.setFrame(frame, display: true)
        player.orderFrontRegardless()
        space.add(player)
    }

    private func makeWindow<Content: View>(frame: NSRect, clickThrough: Bool, content: Content) -> DesktopWindow {
        let window = DesktopWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.canBecomeVisibleWithoutLogin = true
        window.ignoresMouseEvents = clickThrough
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        let hosting = FirstMouseHostingView(rootView: content.preferredColorScheme(.dark))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }
}

/// Lyrics in the lock-screen style, plus the edge glow if it's on.
struct LockScreenLyricsView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        ZStack {
            if settings.lyricsEnabled, settings.lockScreenLyricsStyle != .off {
                DesktopLyricsView(vm: vm,
                                  settings: settings,
                                  styleOverride: settings.lockScreenLyricsStyle,
                                  allowsBackdrop: false)
                    // Keep clear of the player card and the login controls below it.
                    .padding(.bottom, 260)
            }
            if settings.edgeGlowEnabled, vm.nowPlaying.isPlaying {
                EdgeGlowView(vm: vm, settings: settings, audio: vm.audio)
            }
        }
        .ignoresSafeArea()
    }
}

/// Glass player card for the lock screen.
struct LockScreenPlayerCard: View {
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: nowPlaying.artwork, size: 46, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if nowPlaying.isPlaying {
                    AudioBars().frame(width: 18, height: 14)
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressRow(elapsed: nowPlaying.elapsed(at: context.date),
                            duration: nowPlaying.track?.duration ?? 0,
                            onSeek: { nowPlaying.seek(to: $0) })
            }

            HStack(spacing: 28) {
                Spacer()
                ControlButton(symbol: "backward.fill", size: 16) { nowPlaying.previous() }
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                    nowPlaying.playPause()
                }
                ControlButton(symbol: "forward.fill", size: 16) { nowPlaying.next() }
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: LockScreenController.playerSize.width - 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
