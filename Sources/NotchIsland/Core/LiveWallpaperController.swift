import AppKit
import Combine
import MetalKit

/// Shows the live wallpaper: a Metal view just above the desktop picture, behind
/// desktop icons and windows. It pauses whenever it is fully covered.
@MainActor
final class LiveWallpaperController {
    private let vm: NotchViewModel
    private var window: DesktopWindow?
    private var metalView: MTKView?
    private var renderer: WallpaperRenderer?
    private var occlusionObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: NotchViewModel) {
        vm = viewModel
        let settings = viewModel.settings

        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$liveWallpaperScene.map { _ in () }.eraseToAnyPublisher(),
            settings.$liveWallpaperWhen.map { _ in () }.eraseToAnyPublisher(),
            settings.$liveWallpaperReactsToAudio.map { _ in () }.eraseToAnyPublisher(),
            settings.$liveWallpaperPausesOnBattery.map { _ in () }.eraseToAnyPublisher(),
            viewModel.nowPlaying.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            viewModel.battery.$info.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.update() }
            .store(in: &cancellables)
    }

    func update() {
        let settings = vm.settings
        let onBattery = vm.battery.info.map { !$0.isPluggedIn } ?? false
        let wanted = settings.liveWallpaperScene != .off
            && (settings.liveWallpaperWhen == .always || vm.nowPlaying.isPlaying)
            && !(settings.liveWallpaperPausesOnBattery && onBattery)

        vm.audio.use("wallpaper", wanted && settings.liveWallpaperReactsToAudio)

        guard wanted else {
            metalView?.isPaused = true
            window?.orderOut(nil)
            return
        }

        if window == nil { build() }
        guard let window, let metalView else { return }

        let frame = screenFrame()
        window.setFrame(frame, display: true)
        // Render at one pixel per point: half the pixels on Retina, still smooth for these scenes.
        metalView.drawableSize = frame.size
        window.orderFrontRegardless()
        metalView.isPaused = !window.occlusionState.contains(.visible)
    }

    private func screenFrame() -> NSRect {
        let frame = vm.geometry.screenFrame
        if frame.width > 0 { return frame }
        return NSScreen.main?.frame ?? .zero
    }

    private func build() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            vm.wallpaperError = "This Mac has no Metal graphics device."
            return
        }

        let frame = screenFrame()
        let view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.autoresizingMask = [.width, .height]

        do {
            let renderer = try WallpaperRenderer(device: device, pixelFormat: view.colorPixelFormat)
            renderer.provider = { [weak self] in
                self?.inputs() ?? WallpaperInputs(scene: 0, colorA: .zero, colorB: .zero, level: 0, beat: 0)
            }
            view.delegate = renderer
            self.renderer = renderer
            vm.wallpaperError = nil
        } catch {
            vm.wallpaperError = "The wallpaper shader didn't compile: \(error.localizedDescription)"
            return
        }

        let window = DesktopWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Just above the desktop picture; desktop lyrics sit at +2, icons above both.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = view

        // Stop drawing while windows or a full-screen app cover the desktop.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, let view = self.metalView else { return }
                view.isPaused = !window.occlusionState.contains(.visible) || !window.isVisible
            }
        }

        self.window = window
        metalView = view
    }

    // MARK: - Per-frame inputs

    private func inputs() -> WallpaperInputs {
        let settings = vm.settings
        let scene = settings.liveWallpaperScene
        var (colorA, colorB) = scene.defaultColors
        if settings.liveWallpaperAlbumColors, let album = Self.albumColors(vm.nowPlaying.palette) {
            (colorA, colorB) = album
        }

        let now = CFAbsoluteTimeGetCurrent()
        let level: Float
        let beat: Float
        if vm.audio.state == .running {
            level = Float(vm.audio.level)
            beat = Float(exp(-(now - vm.audio.lastBeatTime) * 5))
        } else {
            // No audio access: pulse on each new lyric line, with a slow breath.
            let elapsed = vm.nowPlaying.elapsed(at: Date()) + settings.lyricsOffset
            let line = vm.lyrics.lyrics.flatMap { lyrics in
                LRC.index(at: elapsed, in: lyrics.synced).map { lyrics.synced[$0] }
            }
            let since = line.map { elapsed - $0.time }
            beat = Float(since.map { max(0, 1 - $0 / 0.6) } ?? 0)
            let breath = 0.5 + 0.5 * sin(now * 1.4)
            level = vm.nowPlaying.isPlaying ? Float(0.35 + 0.2 * breath) : 0.15
        }

        return WallpaperInputs(scene: scene.shaderIndex, colorA: colorA, colorB: colorB, level: level, beat: beat)
    }

    /// The album palette as bright shader colors.
    static func albumColors(_ palette: [NSColor]) -> (SIMD4<Float>, SIMD4<Float>)? {
        guard let first = palette.first else { return nil }
        let second = palette.dropFirst().first ?? first
        return (vivid(first), vivid(second))
    }

    static func vivid(_ color: NSColor) -> SIMD4<Float> {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let bright = NSColor(hue: hue, saturation: max(saturation, 0.5), brightness: max(brightness, 0.85), alpha: 1)
            .usingColorSpace(.sRGB) ?? rgb
        return SIMD4(Float(bright.redComponent), Float(bright.greenComponent), Float(bright.blueComponent), 1)
    }
}
