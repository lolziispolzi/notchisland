import CoreImage
import Foundation

/// Gives any wallpaper a frosted-glass finish: soft blur, a little extra color,
/// a light sheen from the top-left, two faint glass panes, a gentle vignette that
/// keeps contrast, and fine grain. Dark images get a weaker sheen so they stay dark.
enum GlassFinish {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func apply(to input: CIImage) -> CIImage {
        let extent = input.extent
        let blurred = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(extent.width) * 0.009)
            .cropped(to: extent)
        let vivid = blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.18])

        let dark = averageLuminance(of: input) < 0.4
        let maps = overlayMaps(dark: dark)
        let light = stretch(CIImage(cgImage: maps.screen), to: extent)
        let shade = stretch(CIImage(cgImage: maps.multiply), to: extent)

        var output = light.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: vivid])
        output = shade.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: output])
        output = grain(extent: extent).applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: output])
        return output.cropped(to: extent)
    }

    /// Average brightness from 0 to 1.
    static func averageLuminance(of image: CIImage) -> Double {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    /// Low-resolution light (screen) and shade (multiply) maps, stretched to full size later.
    /// Same math as the prototype in scripts/wallpapers.
    static func overlayMaps(dark: Bool, width: Int = 320, height: Int = 200) -> (screen: CGImage, multiply: CGImage) {
        var screen = [UInt8](repeating: 0, count: width * height)
        var multiply = [UInt8](repeating: 255, count: width * height)
        let sheenStrength = dark ? 0.09 : 0.16
        let paneStrength = dark ? 0.05 : 0.08
        let vignetteStrength = dark ? 0.35 : 0.12

        for row in 0..<height {
            let y = Double(row) / Double(height - 1)          // 0 at the top
            for column in 0..<width {
                let x = Double(column) / Double(width - 1)
                let t = max(0, min(1, 1 - (x * 0.7 + y) / 1.2))
                let sheen = sheenStrength * t * t
                let band = 0.5 + 0.5 * cos((x * 1.3 - y * 0.9) * .pi * 2.2 + 0.6)
                let pane = paneStrength * pow(band, 6)
                let lightValue = 1 - (1 - sheen) * (1 - pane)
                let v = (x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5)
                let shadeValue = 1 - v * vignetteStrength
                screen[row * width + column] = UInt8(max(0, min(255, lightValue * 255)))
                multiply[row * width + column] = UInt8(max(0, min(255, shadeValue * 255)))
            }
        }
        return (grayImage(screen, width: width, height: height), grayImage(multiply, width: width, height: height))
    }

    private static func grayImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }

    private static func stretch(_ image: CIImage, to extent: CGRect) -> CIImage {
        let scaleX = extent.width / image.extent.width
        let scaleY = extent.height / image.extent.height
        return image
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .clampedToExtent()
            .cropped(to: extent)
    }

    /// Mid-gray noise with very low contrast; soft-light blended it reads as fine grain.
    private static func grain(extent: CGRect) -> CIImage {
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        let amount: CGFloat = 0.06
        return noise
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.5 - amount / 2, y: 0.5 - amount / 2, z: 0.5 - amount / 2, w: 1),
            ])
            .cropped(to: extent)
    }
}
