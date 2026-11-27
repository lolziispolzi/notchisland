import SwiftUI

/// Outline of the screen with rounded corners, dipping around the notch if there is one.
/// Coordinates: origin top-left, `notch` in the same space.
struct ScreenOutline: Shape {
    var notch: CGRect?
    var cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))

        if let notch, notch.width > 0 {
            let nr = min(8, notch.height / 2)
            p.addLine(to: CGPoint(x: notch.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: notch.minX, y: notch.maxY - nr))
            p.addQuadCurve(to: CGPoint(x: notch.minX + nr, y: notch.maxY),
                           control: CGPoint(x: notch.minX, y: notch.maxY))
            p.addLine(to: CGPoint(x: notch.maxX - nr, y: notch.maxY))
            p.addQuadCurve(to: CGPoint(x: notch.maxX, y: notch.maxY - nr),
                           control: CGPoint(x: notch.maxX, y: notch.maxY))
            p.addLine(to: CGPoint(x: notch.maxX, y: rect.minY))
        }

        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

enum GlowPulse {
    /// Brightness without audio: a slow breath, plus a flash when a new lyric line starts.
    static func intensity(sinceLineStart: Double?, time: Double) -> Double {
        let breath = 0.5 + 0.5 * sin(time * 1.6)
        let flash = sinceLineStart.map { max(0, 1 - $0 / 0.8) } ?? 0
        return min(1, 0.3 + 0.15 * breath + 0.55 * flash)
    }
}

/// A line of light around the screen edge, in the album's color, pulsing with the music.
struct EdgeGlowView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var audio: AudioLevelMonitor

    /// The notch in this view's coordinates, or nil on screens without one.
    private var notch: CGRect? {
        let geometry = vm.geometry
        guard geometry.hasNotch else { return nil }
        return CGRect(x: geometry.notchRect.minX - geometry.screenFrame.minX,
                      y: 0,
                      width: geometry.notchRect.width,
                      height: geometry.notchRect.height)
    }

    var body: some View {
        Ticker(every: 1.0 / 30) { context in
            let color = vm.nowPlaying.accentColor
            let intensity = currentIntensity(at: context.date)
            let outline = ScreenOutline(notch: notch)
            ZStack {
                outline
                    .stroke(color.opacity(0.35 * intensity), lineWidth: 36)
                    .blur(radius: 26)
                outline
                    .stroke(color.opacity(0.75 * intensity), lineWidth: 10)
                    .blur(radius: 6)
                outline
                    .stroke(color.opacity(0.4 + 0.6 * intensity), lineWidth: 2.5)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .allowsHitTesting(false)
    }

    private func currentIntensity(at date: Date) -> Double {
        if settings.edgeGlowReactsToAudio, audio.state == .running {
            return 0.2 + 0.8 * audio.level
        }
        let elapsed = vm.nowPlaying.elapsed(at: date) + settings.lyricsOffset
        let line = vm.lyrics.lyrics.flatMap { lyrics in
            LRC.index(at: elapsed, in: lyrics.synced).map { lyrics.synced[$0] }
        }
        let since = line.map { elapsed - $0.time }
        let paused = !vm.nowPlaying.isPlaying
        let value = GlowPulse.intensity(sinceLineStart: since, time: date.timeIntervalSinceReferenceDate)
        return paused ? value * 0.4 : value
    }
}

extension NowPlayingService {
    /// A bright version of the album's main color, or a soft blue without artwork.
    var accentColor: Color {
        guard let first = palette.first?.usingColorSpace(.sRGB) else {
            return Color(red: 0.42, green: 0.58, blue: 1)
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        first.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: Double(max(saturation, 0.55)), brightness: Double(max(brightness, 0.9)))
    }
}
