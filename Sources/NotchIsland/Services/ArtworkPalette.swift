import AppKit

/// Picks a couple of strong colors from album artwork, for tinted backgrounds.
enum ArtworkPalette {
    static func colors(from image: NSImage) -> [NSColor] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return [] }

        // Shrinking the image averages it into a few representative pixels.
        let side = 6
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        struct Candidate {
            let color: NSColor
            let hue: CGFloat
            let score: CGFloat
        }

        var candidates: [Candidate] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let color = NSColor(srgbRed: CGFloat(pixels[index]) / 255,
                                green: CGFloat(pixels[index + 1]) / 255,
                                blue: CGFloat(pixels[index + 2]) / 255,
                                alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            guard brightness > 0.12 else { continue }
            candidates.append(Candidate(color: color, hue: hue, score: saturation * 0.7 + brightness * 0.3))
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return [NSColor(white: 0.18, alpha: 1)]
        }
        let others = candidates.filter { hueDistance($0.hue, best.hue) > 0.08 }
        let second = others.max(by: { $0.score < $1.score })
            ?? candidates.min(by: { $0.score < $1.score })
            ?? best
        return [best.color, second.color]
    }

    static func hueDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let distance = abs(a - b)
        return min(distance, 1 - distance)
    }
}

extension NSColor {
    /// Same hue and saturation, with brightness scaled and clamped, for dark backgrounds.
    func dimmed(to factor: CGFloat, maxBrightness: CGFloat = 0.6) -> NSColor {
        let rgb = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: saturation, brightness: min(brightness * factor, maxBrightness), alpha: alpha)
    }
}
