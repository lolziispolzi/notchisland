import AppKit
import Combine
import os
import SwiftUI

/// Diagnostics for the lock screen, shown in Settings.
struct LockScreenStatus: Equatable {
    var lastLocked: Date?
    var lastUnlocked: Date?
    /// What happened the last time the screen locked.
    var lastAttempt = "The screen hasn't been locked since NotchIsland started."
}

/// What the lock screen shows. Clicking the cover steps through the modes.
enum LockScreenMode: Equatable {
    /// A glass player card under the clock.
    case compact
    /// The cover, large, with the screen in the album's colors.
    case cover
    /// Lyrics fill the screen.
    case lyrics

    func next(hasLyrics: Bool) -> LockScreenMode {
        switch self {
        case .compact: .cover
        case .cover: hasLyrics ? .lyrics : .compact
        case .lyrics: .compact
        }
    }
}

/// While the screen is locked and music plays, shows the player, cover and lyrics
/// above the lock screen, using a private macOS API (see `SkyLightSpace`).
///
/// Two windows: a full-screen one that never takes clicks (background color, lyrics,
/// glow), and a small clickable one for the cover and the player card. Keeping the
/// clickable area small leaves the password field usable.
@MainActor
final class LockScreenController {
    private let vm: NotchViewModel
    private let glow: EdgeGlowController
    private var stageWindow: DesktopWindow?
    private var playerWindow: DesktopWindow?
    private var observers: [DistributedObserver] = []
    private var cancellables = Set<AnyCancellable>()
    private var lockPoll: Timer?
    private var previewWork: DispatchWorkItem?
    private var isPreviewing = false
    private(set) var isLocked = false
    private let log = OSLog(subsystem: "io.github.notchisland", category: "lockscreen")

    /// Above the lock screen without private APIs, for windows allowed before login.
    /// Used together with `SkyLightSpace.lockScreen`; whichever works on this macOS wins.
    private static let shieldingLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

    static let cardSize = CGSize(width: 340, height: 150)
    static let coverSize: CGFloat = 300
    static let coverSpacing: CGFloat = 16

    /// False when the private API is missing on this macOS version.
    static var isSupported: Bool { SkyLightSpace.lockScreen != nil }

    init(viewModel: NotchViewModel, glow: EdgeGlowController) {
        vm = viewModel
        self.glow = glow

        observers.append(DistributedObserver("com.apple.screenIsLocked") { [weak self] _ in
            MainActor.assumeIsolated { self?.setLocked(true) }
        })
        observers.append(DistributedObserver("com.apple.screenIsUnlocked") { [weak self] _ in
            MainActor.assumeIsolated { self?.setLocked(false) }
        })

        let settings = viewModel.settings
        Publishers.CombineLatest4(
            settings.$lockScreenEnabled.map { _ in () },
            viewModel.$lockScreenMode.map { _ in () },
            viewModel.nowPlaying.$track.map { _ in () },
            viewModel.lyrics.$lyrics.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.update() }
        .store(in: &cancellables)

        // The app may start while the screen is already locked.
        if Self.screenIsLockedNow() { setLocked(true) }
    }

    /// Reads the lock state from the window server.
    static func screenIsLockedNow() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        os_log("Screen %{public}@", log: log, type: .info, locked ? "locked" : "unlocked")
        if locked {
            vm.lockScreenStatus.lastLocked = Date()
        } else {
            vm.lockScreenStatus.lastUnlocked = Date()
        }
        glow.isLocked = locked
        lockPoll?.invalidate()
        lockPoll = nil
        if locked {
            // Safety net: if the unlock notification is missed, notice within 2 seconds,
            // so nothing stays on top of the desktop.
            lockPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if !Self.screenIsLockedNow() { self?.setLocked(false) }
                }
            }
        } else {
            vm.lockScreenMode = .compact
        }
        update()
    }

    /// Shows the lock-screen layout on the desktop for 10 seconds, to try it out.
    func preview() {
        previewWork?.cancel()
        isPreviewing = true
        update()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.isPreviewing = false
                self?.update()
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func update() {
        let settings = vm.settings
        let space = SkyLightSpace.lockScreen
        let onLockScreen = isLocked && settings.lockScreenEnabled
        if isLocked {
            if !settings.lockScreenEnabled {
                record("Locked, but \"Show the player on the lock screen\" is off.")
            } else if vm.nowPlaying.track == nil {
                record("Locked, but nothing was playing in Spotify or Music.")
            }
        }
        guard (onLockScreen || isPreviewing), vm.nowPlaying.track != nil else {
            stageWindow?.orderOut(nil)
            playerWindow?.orderOut(nil)
            return
        }

        let screen = vm.geometry.screenFrame.width > 0
            ? vm.geometry.screenFrame
            : (NSScreen.main?.frame ?? .zero)

        let stage = stageWindow ?? makeWindow(frame: screen, clickThrough: true,
                                              content: LockScreenStage(vm: vm, settings: settings))
        stageWindow = stage
        stage.setFrame(screen, display: true)
        stage.orderFrontRegardless()

        let playerFrame = Self.playerFrame(mode: vm.lockScreenMode, in: screen)
        let player = playerWindow ?? makeWindow(frame: playerFrame, clickThrough: false,
                                                content: LockScreenPlayer(vm: vm))
        playerWindow = player
        player.setFrame(playerFrame, display: true, animate: false)
        player.orderFrontRegardless()

        if onLockScreen {
            if let space {
                space.add(stage)
                space.add(player)
                record("Locked with music playing. Moved windows \(stage.windowNumber) and \(player.windowNumber) into the lock-screen space: \(space.setupSummary).")
            } else {
                record("Locked with music playing, but this macOS has no SkyLight lock-screen functions. Tried the fallback window level only.")
            }
        }
    }

    private func record(_ message: String) {
        guard vm.lockScreenStatus.lastAttempt != message else { return }
        vm.lockScreenStatus.lastAttempt = message
        os_log("%{public}@", log: log, type: .info, message)
    }

    /// Where the clickable player sits for each mode, in screen coordinates.
    static func playerFrame(mode: LockScreenMode, in screen: NSRect) -> NSRect {
        let card = cardSize
        switch mode {
        case .compact:
            return NSRect(x: screen.midX - card.width / 2,
                          y: screen.minY + screen.height * 0.36,
                          width: card.width,
                          height: card.height)
        case .cover:
            let height = coverSize + coverSpacing + card.height
            return NSRect(x: screen.midX - card.width / 2,
                          y: screen.minY + screen.height * 0.2,
                          width: card.width,
                          height: height)
        case .lyrics:
            return NSRect(x: screen.midX - card.width / 2,
                          y: screen.minY + screen.height * 0.18,
                          width: card.width,
                          height: card.height)
        }
    }

    private func makeWindow<Content: View>(frame: NSRect, clickThrough: Bool, content: Content) -> DesktopWindow {
        let window = DesktopWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = Self.shieldingLevel
        // Not "all spaces": the window is moved into the lock-screen space instead.
        window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        window.canBecomeVisibleWithoutLogin = true
        window.ignoresMouseEvents = clickThrough
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        let hosting = FirstMouseHostingView(rootView: content.compatDarkScheme())
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        return window
    }
}

/// Full-screen, click-through layer: album colors, lyrics and the edge glow.
struct LockScreenStage: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if vm.lockScreenMode != .compact {
                    AlbumBackdrop(colors: vm.nowPlaying.palette)
                        .transition(.opacity)
                }
                if vm.lockScreenMode == .lyrics, settings.lyricsEnabled {
                    DesktopLyricsView(vm: vm,
                                      settings: settings,
                                      styleOverride: settings.lockScreenLyricsStyle == .off ? .bigLyrics : settings.lockScreenLyricsStyle,
                                      allowsBackdrop: false)
                        // Below the clock, above the player card.
                        .padding(.top, geometry.size.height * 0.22)
                        .padding(.bottom, geometry.size.height * 0.36)
                        .transition(.opacity)
                }
                if settings.edgeGlowEnabled, vm.nowPlaying.isPlaying {
                    EdgeGlowView(vm: vm, settings: settings, audio: vm.audio)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .animation(.easeInOut(duration: 0.6), value: vm.lockScreenMode)
    }
}

/// Clickable part: the large cover (in cover mode) and the glass player card.
struct LockScreenPlayer: View {
    @ObservedObject var vm: NotchViewModel

    private var nowPlaying: NowPlayingService { vm.nowPlaying }

    var body: some View {
        VStack(spacing: LockScreenController.coverSpacing) {
            if vm.lockScreenMode == .cover {
                ArtworkView(image: nowPlaying.artwork, size: LockScreenController.coverSize, cornerRadius: 22)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                    .onTapGesture(perform: nextMode)
                    .compatHelp("Click for lyrics")
                    .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
            }
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: vm.lockScreenMode)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: nowPlaying.artwork, size: 46, cornerRadius: 9)
                    .onTapGesture(perform: nextMode)
                    .compatHelp("Click to enlarge")
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if nowPlaying.isPlaying {
                    AudioBars().frame(width: 18, height: 14)
                }
            }

            Ticker(every: 1) { context in
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
                ControlButton(symbol: "quote.bubble", size: 12, isActive: vm.lockScreenMode == .lyrics) {
                    vm.lockScreenMode = vm.lockScreenMode == .lyrics ? .compact : .lyrics
                }
                .compatHelp("Lyrics")
            }
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(width: LockScreenController.cardSize.width - 20, height: LockScreenController.cardSize.height - 10)
        .background(FrostedBackground().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    private func nextMode() {
        vm.lockScreenMode = vm.lockScreenMode.next(hasLyrics: vm.lyrics.lyrics != nil)
    }
}
