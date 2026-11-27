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
                Ticker(every: 0.25) { context in
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
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(centered ? .center : .leading)
                        .lineSpacing(spacing / 2)
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                }
            }
        } else if lyrics.state == .loading {
            Spinner()
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
            .foregroundColor(.white.opacity(0.55))
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

    /// Vertical center of each line inside the stack, measured after layout.
    @State private var lineCenters: [Int: CGFloat] = [:]

    var body: some View {
        // Moves the whole stack instead of scrolling, so the current line stays centered
        // on every macOS version (ScrollViewReader needs macOS 11).
        GeometryReader { geometry in
            VStack(alignment: centered ? .center : .leading, spacing: spacing) {
                ForEach(lines) { line in
                    Text(line.text.isEmpty ? "♪" : line.text)
                        .font(.system(size: fontSize, weight: line.id == current ? .bold : .semibold))
                        .foregroundColor(.white.opacity(opacity(for: line.id)))
                        .blur(radius: blur(for: line.id))
                        .scaleEffect(line.id == current ? 1 : 0.97, anchor: centered ? .center : .leading)
                        .multilineTextAlignment(centered ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { lineGeometry in
                            Color.clear.preference(
                                key: LyricLineCentersKey.self,
                                value: [line.id: lineGeometry.frame(in: .named("lyricsStack")).midY])
                        })
                }
            }
            .coordinateSpace(name: "lyricsStack")
            .onPreferenceChange(LyricLineCentersKey.self) { lineCenters = $0 }
            .offset(y: geometry.size.height / 2 - (current.flatMap { lineCenters[$0] } ?? 0))
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: current)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
        }
        .mask(
            LinearGradient(gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ]), startPoint: .top, endPoint: .bottom)
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
        Ticker(every: 0.25) { context in
            let line = lyrics.currentLine(at: nowPlaying.elapsed(at: context.date))
            ZStack {
                Text(line.map { $0.text.isEmpty ? "♪" : $0.text } ?? "♪")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(line?.id ?? -1)
                    .transition(.pushFromBottom)
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
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                ControlButton(symbol: "backward.fill", size: 11) { nowPlaying.previous() }
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 14) {
                    nowPlaying.playPause()
                }
                ControlButton(symbol: "forward.fill", size: 11) { nowPlaying.next() }
                ControlButton(symbol: "quote.bubble.fill", size: 11, isActive: true, action: onShowPlayer)
                    .compatHelp("Back to the player")
            }
        }
    }
}

private struct LyricLineCentersKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
