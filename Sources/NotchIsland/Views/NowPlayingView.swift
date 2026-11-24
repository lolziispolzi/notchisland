import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        if let track = nowPlaying.track {
            HStack(spacing: 14) {
                ArtworkView(image: nowPlaying.artwork, size: 84, cornerRadius: 14)

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    // Redraws once a second only while the island is open.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ProgressRow(elapsed: nowPlaying.elapsed(at: context.date), duration: track.duration)
                    }

                    HStack(spacing: 18) {
                        ControlButton(symbol: "backward.fill", size: 14) { nowPlaying.previous() }
                        ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                            nowPlaying.playPause()
                        }
                        ControlButton(symbol: "forward.fill", size: 14) { nowPlaying.next() }
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
                    Text("Play something in Music or Spotify.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
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
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.5))
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

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(TimeFormat.string(elapsed))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text(TimeFormat.string(duration))
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
