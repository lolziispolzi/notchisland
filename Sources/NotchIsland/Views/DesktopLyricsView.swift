import SwiftUI

/// Content of the desktop lyrics window, in the style picked in Settings.
struct DesktopLyricsView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    /// Used by the lock screen, which has its own style setting.
    var styleOverride: DesktopLyricsStyle?
    /// The lock screen never fills the screen, so the login controls stay visible.
    var allowsBackdrop = true

    private var scale: CGFloat { settings.desktopLyricsSize.scale }
    private var nowPlaying: NowPlayingService { vm.nowPlaying }
    private var style: DesktopLyricsStyle { styleOverride ?? settings.desktopLyricsStyle }

    var body: some View {
        ZStack {
            // The live wallpaper replaces the album-color backdrop when it's on.
            if allowsBackdrop, settings.desktopLyricsTint, settings.liveWallpaperScene == .off {
                AlbumBackdrop(colors: nowPlaying.palette)
                    .transition(.opacity)
            }

            switch style {
            case .stars:
                ConstellationLyricsView(nowPlaying: nowPlaying,
                                        lyrics: vm.lyrics,
                                        settings: settings,
                                        color: nowPlaying.accentColor,
                                        scale: scale)
            case .coverAndLyrics:
                coverAndLyrics
            case .bigLyrics:
                bigLyrics
            case .bottomLine:
                bottomLine
            case .off:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: nowPlaying.track)
        .animation(.easeInOut(duration: 1.2), value: nowPlaying.palette)
        .preferredColorScheme(.dark)
    }

    // MARK: - Cover and lyrics

    private var coverAndLyrics: some View {
        HStack(alignment: .center, spacing: 64 * scale) {
            VStack(spacing: 14 * scale) {
                ArtworkView(image: nowPlaying.artwork, size: 280 * scale, cornerRadius: 20 * scale)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
                VStack(spacing: 4) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 22 * scale, weight: .bold))
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 16 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ProgressRow(elapsed: nowPlaying.elapsed(at: context.date),
                                duration: nowPlaying.track?.duration ?? 0)
                }
                .frame(width: 280 * scale)
            }
            .frame(width: 300 * scale)

            LyricsLinesView(nowPlaying: nowPlaying,
                            lyrics: vm.lyrics,
                            fontSize: 30 * scale,
                            spacing: 18 * scale)
                .frame(width: 640 * scale, height: 460 * scale)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(allowsBackdrop && settings.desktopLyricsTint ? 0 : 0.6), radius: 8)
    }

    // MARK: - Big lyrics

    private var bigLyrics: some View {
        VStack(spacing: 28 * scale) {
            LyricsLinesView(nowPlaying: nowPlaying,
                            lyrics: vm.lyrics,
                            fontSize: 46 * scale,
                            centered: true,
                            spacing: 26 * scale)
                .frame(maxWidth: 1100 * scale)
                .frame(height: 520 * scale)
            HStack(spacing: 10) {
                ArtworkView(image: nowPlaying.artwork, size: 36, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 13, weight: .semibold))
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(allowsBackdrop && settings.desktopLyricsTint ? 0 : 0.6), radius: 10)
    }

    // MARK: - Bottom line

    private var bottomLine: some View {
        VStack {
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let elapsed = nowPlaying.elapsed(at: context.date)
                let index = vm.lyrics.currentIndex(at: elapsed)
                let lines = vm.lyrics.lyrics?.synced ?? []
                let current = index.map { lines[$0].text } ?? ""
                let next = index.map { $0 + 1 < lines.count ? lines[$0 + 1].text : "" }
                    ?? lines.first?.text ?? ""

                VStack(spacing: 6 * scale) {
                    Text(current.isEmpty ? "♪" : current)
                        .font(.system(size: 30 * scale, weight: .bold))
                        .id(index ?? -1)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                    if !next.isEmpty {
                        Text(next)
                            .font(.system(size: 18 * scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 32 * scale)
                .padding(.vertical, 18 * scale)
                .frame(maxWidth: 1000 * scale)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28 * scale, style: .continuous))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: index)
            }
            .padding(.bottom, 140)
        }
        .foregroundStyle(.white)
    }
}

/// Full-screen gradient made from the album's colors.
struct AlbumBackdrop: View {
    let colors: [NSColor]

    private var first: Color {
        colors.first.map { Color(nsColor: $0.dimmed(to: 0.7)) } ?? Color(white: 0.1)
    }

    private var second: Color {
        colors.dropFirst().first.map { Color(nsColor: $0.dimmed(to: 0.45, maxBrightness: 0.4)) } ?? Color(white: 0.04)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [first, second], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [first.opacity(0.7), .clear],
                           center: UnitPoint(x: 0.25, y: 0.3),
                           startRadius: 0,
                           endRadius: 900)
            Color.black.opacity(0.25)
        }
        .ignoresSafeArea()
    }
}
