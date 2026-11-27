import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    var showsLyricsButton = false
    var onShowLyrics: () -> Void = {}

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 14) {
                ArtworkView(image: nowPlaying.artwork, size: 84, cornerRadius: 14)
                    .onTapGesture { nowPlaying.openPlayer() }
                    .compatHelp("Open \(nowPlaying.player?.appName ?? "player")")

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(nowPlaying.player.map { "\(track.artist) · \($0.appName)" } ?? track.artist)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    // Redraws once a second only while the island is open.
                    Ticker(every: 1) { context in
                        ProgressRow(elapsed: nowPlaying.elapsed(at: context.date),
                                    duration: track.duration,
                                    onSeek: { nowPlaying.seek(to: $0) })
                    }

                    HStack(spacing: showsLyricsButton ? 8 : 12) {
                        ControlButton(symbol: "shuffle", size: 11, isActive: nowPlaying.shuffle) {
                            nowPlaying.toggleShuffle()
                        }
                        ControlButton(symbol: "backward.fill", size: 14) { nowPlaying.previous() }
                        ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                            nowPlaying.playPause()
                        }
                        ControlButton(symbol: "forward.fill", size: 14) { nowPlaying.next() }
                        ControlButton(symbol: "repeat", size: 11, isActive: nowPlaying.repeating) {
                            nowPlaying.toggleRepeat()
                        }
                        if showsLyricsButton {
                            ControlButton(symbol: "quote.bubble", size: 11, isActive: false, action: onShowLyrics)
                                .compatHelp("Show lyrics")
                        }
                    }
                }
                .frame(width: 220, alignment: .leading)
            }
        } else {
            HStack(spacing: 14) {
                ArtworkView(image: nil, size: 84, cornerRadius: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Play something in Spotify or Music.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                    Button("Open Spotify") { nowPlaying.openPlayer() }
                        .buttonStyle(PillButtonStyle())
                        .padding(.top, 4)
                }
            }
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    SymbolImage("music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ProgressRow: View {
    let elapsed: Double
    let duration: Double
    /// Called with the target position in seconds when the user drags the bar.
    var onSeek: ((Double) -> Void)?

    @State private var dragFraction: CGFloat?

    private var fraction: CGFloat {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    private var shownElapsed: Double {
        dragFraction.map { Double($0) * duration } ?? elapsed
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(TimeFormat.string(shownElapsed))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white).frame(width: geo.size.width * fraction)
                }
                .frame(height: dragFraction == nil ? 4 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard onSeek != nil, duration > 0, geo.size.width > 0 else { return }
                            dragFraction = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            if let dragFraction { onSeek?(Double(dragFraction) * duration) }
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 12)
            Text(TimeFormat.string(duration))
        }
        .font(Font.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundColor(.white.opacity(0.6))
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var isActive: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SymbolImage(symbol)
                .font(.system(size: size, weight: isActive == nil ? .regular : .semibold))
                .foregroundColor(isActive == false ? Color.white.opacity(0.4) : Color.white)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum TimeFormat {
    /// "3:05" or "1:02:03".
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
