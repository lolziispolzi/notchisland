import SwiftUI

/// The state of one frame of the Stars style: which line, how many words are lit.
struct ConstellationFrame: Equatable {
    let lineID: Int
    let words: [String]
    let visibleCount: Int
    let currentWord: String

    /// LRC times whole lines, so words are spread evenly over 85% of the line.
    static func make(lines: [LyricLine], elapsed: Double) -> ConstellationFrame? {
        guard let index = LRC.index(at: elapsed, in: lines) else { return nil }
        let line = lines[index]
        let words = line.text.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return ConstellationFrame(lineID: line.id, words: [], visibleCount: 0, currentWord: "♪")
        }
        let end = index + 1 < lines.count ? lines[index + 1].time : line.time + 4
        let duration = max(end - line.time, 0.5)
        let progress = min(max((elapsed - line.time) / (duration * 0.85), 0), 1)
        let visible = max(1, min(words.count, Int((progress * Double(words.count)).rounded(.up))))
        return ConstellationFrame(lineID: line.id, words: words, visibleCount: visible, currentWord: words[visible - 1])
    }
}

/// Places the stars of a line. Deterministic per line, so a line keeps its shape.
enum ConstellationLayout {
    static func points(count: Int, seed: Int, size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        var state = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 1_013_904_223) | 1
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        return (0..<count).map { index in
            let base = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let x = (0.08 + 0.84 * base + (random() - 0.5) * 0.08) * size.width
            let y = (0.15 + 0.7 * random()) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

/// Lyrics drawn as constellations: each sung word lights a star, linked to the last;
/// the word being sung shows large underneath.
struct ConstellationLyricsView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var settings: AppSettings
    let color: Color
    let scale: CGFloat

    var body: some View {
        Ticker(every: 1.0 / 30) { context in
            let elapsed = nowPlaying.elapsed(at: context.date) + settings.lyricsOffset
            let frame = ConstellationFrame.make(lines: lyrics.lyrics?.synced ?? [], elapsed: elapsed)
            ZStack {
                if let frame {
                    constellation(frame)
                        .id(frame.lineID)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeInOut(duration: 0.5), value: frame?.lineID)
        }
    }

    private func constellation(_ frame: ConstellationFrame) -> some View {
        let size = CGSize(width: 620 * scale, height: 240 * scale)
        let points = ConstellationLayout.points(count: frame.words.count, seed: frame.lineID, size: size)

        return VStack(spacing: 12 * scale) {
            ZStack(alignment: .topLeading) {
                Path { path in
                    for (index, point) in points.prefix(frame.visibleCount).enumerated() {
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(color.opacity(0.55), lineWidth: 1)

                ForEach(0..<frame.visibleCount, id: \.self) { index in
                    let isCurrent = index == frame.visibleCount - 1
                    VStack(spacing: 3 * scale) {
                        Text(frame.words[index])
                            .font(.system(size: 13 * scale, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                        SymbolImage("sparkle")
                            .font(.system(size: (isCurrent ? 20 : 10) * scale))
                            .foregroundColor(isCurrent ? .white : color)
                            .shadow(color: color, radius: isCurrent ? 10 : 4)
                    }
                    .position(x: points[index].x, y: points[index].y - 10 * scale)
                }
            }
            .frame(width: size.width, height: size.height)

            Text(frame.currentWord)
                .font(.system(size: 76 * scale, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.8), radius: 20)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: frame.visibleCount)
        }
    }
}
