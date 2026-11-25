import SwiftUI

/// Lyrics for the current song, or a status message. Synced lyrics scroll with the song.
struct LyricsLinesView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    var fontSize: CGFloat = 15
    var centered = false
    var spacing: CGFloat = 8

    var body: some View {
        if let current = lyrics.lyrics {
            if current.isSynced {
                // Checks four times a second which line is being sung.
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    SyncedLyricsScroller(lines: current.synced,
                                         current: lyrics.currentIndex(at: nowPlaying.elapsed(at: context.date)),
                                         fontSize: fontSize,
                                         centered: centered,
                                         spacing: spacing)
                }
            } else if current.instrumental && current.plain.isEmpty {
                message("♪ Instrumental")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(current.plain.joined(separator: "\n"))
                        .font(.system(size: fontSize * 0.85, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(centered ? .center : .leading)
                        .lineSpacing(spacing / 2)
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                }
            }
        } else if lyrics.state == .loading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lyrics.notFound {
            message("No lyrics found for this song")
        } else if let error = lyrics.state.errorMessage {
            VStack(spacing: 6) {
                message(error)
                Button("Try Again") { lyrics.retry() }
                    .buttonStyle(PillButtonStyle())
            }
        } else {
            message("Lyrics show here while a song plays")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(12, fontSize * 0.75), weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
    }
}

/// Scrolls so the current line sits in the middle; nearby lines fade out.
struct SyncedLyricsScroller: View {
    let lines: [LyricLine]
    let current: Int?
    let fontSize: CGFloat
    let centered: Bool
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: centered ? .center : .leading, spacing: spacing) {
                        ForEach(lines) { line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: fontSize, weight: line.id == current ? .bold : .semibold))
                                .foregroundStyle(.white.opacity(opacity(for: line.id)))
                                .blur(radius: blur(for: line.id))
                                .scaleEffect(line.id == current ? 1 : 0.97, anchor: centered ? .center : .leading)
                                .multilineTextAlignment(centered ? .center : .leading)
                                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                                .id(line.id)
                        }
                    }
                    // Room above and below so the first and last lines can reach the middle.
                    .padding(.vertical, geometry.size.height / 2)
                }
                .scrollDisabled(true)
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
                .onChange(of: current) { _, new in
                    guard let new else { return }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .animation(.easeOut(duration: 0.3), value: current)
    }

    private func distance(to id: Int) -> Int {
        guard let current else { return 2 }
        return abs(id - current)
    }

    private func opacity(for id: Int) -> Double {
        switch distance(to: id) {
        case 0: 1
        case 1: 0.5
        case 2: 0.32
        default: 0.2
        }
    }

    private func blur(for id: Int) -> CGFloat {
        distance(to: id) >= 2 ? 0.8 : 0
    }
}

/// The line being sung, shown under the notch while the island is closed.
struct ClosedLyricLine: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let line = lyrics.currentLine(at: nowPlaying.elapsed(at: context.date))
            ZStack {
                Text(line.map { $0.text.isEmpty ? "♪" : $0.text } ?? "♪")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(line?.id ?? -1)
                    .transition(.push(from: .bottom))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: line?.id)
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }
}

/// Small player used next to the lyrics in the Music tab.
struct CompactPlayer: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let onShowPlayer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(image: nowPlaying.artwork, size: 56, cornerRadius: 10)
                .onTapGesture { nowPlaying.openPlayer() }
            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.track?.title ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(nowPlaying.track?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                ControlButton(symbol: "backward.fill", size: 11) { nowPlaying.previous() }
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 14) {
                    nowPlaying.playPause()
                }
                ControlButton(symbol: "forward.fill", size: 11) { nowPlaying.next() }
                ControlButton(symbol: "quote.bubble.fill", size: 11, isActive: true, action: onShowPlayer)
                    .help("Back to the player")
            }
        }
    }
}
