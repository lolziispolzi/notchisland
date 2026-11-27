import CoreGraphics
import Foundation

/// A wallpaper design: Claude picks the style and colors, `WallpaperPainter` draws it.
struct WallpaperRecipe: Codable, Equatable {
    var name: String
    /// "light" or "dark".
    var theme: String
    /// "mesh", "waves", "ribbons", "hills" or "arcs".
    var style: String
    /// Two hex colors: top, then bottom.
    var background: [String]
    /// Three to five hex colors, back to front.
    var colors: [String]
    var description: String
}

enum WallpaperDesignerError: LocalizedError, Equatable {
    case missingKey
    case refused
    case api(status: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key first."
        case .refused: "Claude declined to design that one. Try describing it differently."
        case .api(let status, let message): "The Claude API returned \(status): \(message)"
        case .badResponse: "Claude's reply couldn't be read. Try again."
        }
    }
}

/// Asks Claude to design a wallpaper from a description. Calls the Messages API over
/// HTTP (there is no official Swift SDK) with structured outputs, so the reply always
/// matches the recipe schema.
enum WallpaperDesigner {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"
    static let apiVersion = "2026-10-21"
    /// Lets the API retry on another model if a safety check declines the request.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let keychainAccount = "anthropic-api-key"

    static let systemPrompt = """
    You design desktop wallpapers for a Mac. The app paints your design in one of five styles:
    - mesh: large, soft, blended color glows over the background
    - waves: stacked wavy bands from the middle of the screen down
    - ribbons: two or three smooth glowing ribbons across the screen
    - hills: layered hill silhouettes in the lower half, like a calm landscape
    - arcs: concentric rings spreading from a corner
    Pick the style and colors that best fit the request. Colors are #RRGGBB.
    background: exactly two colors, top then bottom. colors: three to five colors, from back to front.
    Light wallpapers keep the background light and soft. Dark wallpapers keep it deep but not pure black,
    so icons and window shadows stay readable. Favor harmonious, calm palettes over loud ones.
    name: two or three words. description: one short sentence about the mood.
    """

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "theme": ["type": "string", "enum": ["light", "dark"]],
            "style": ["type": "string", "enum": ["mesh", "waves", "ribbons", "hills", "arcs"]],
            "background": ["type": "array", "items": ["type": "string"]],
            "colors": ["type": "array", "items": ["type": "string"]],
            "description": ["type": "string"],
        ],
        "required": ["name", "theme", "style", "background", "colors", "description"],
        "additionalProperties": false,
    ]

    static func requestBody(prompt: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "fallbacks": "default",
        ]
    }

    static func design(prompt: String, apiKey: String) async throws -> WallpaperRecipe {
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(prompt: prompt))

        let (data, response) = try await URLSession.shared.compatData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (error?["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw WallpaperDesignerError.api(status: status, message: message)
        }
        return try parse(responseData: data)
    }

    /// Reads the recipe from a Messages API response.
    static func parse(responseData: Data) throws -> WallpaperRecipe {
        guard let json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] else {
            throw WallpaperDesignerError.badResponse
        }
        if json["stop_reason"] as? String == "refusal" {
            throw WallpaperDesignerError.refused
        }
        // Thinking blocks may come first; the recipe is in the text block.
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let recipe = try? JSONDecoder().decode(WallpaperRecipe.self, from: Data(text.utf8))
        else { throw WallpaperDesignerError.badResponse }
        return sanitized(recipe)
    }

    /// Repairs anything the painter can't use: unknown style, bad hex, wrong color counts.
    static func sanitized(_ recipe: WallpaperRecipe) -> WallpaperRecipe {
        var result = recipe
        let dark = recipe.theme == "dark"
        result.theme = dark ? "dark" : "light"
        if !["mesh", "waves", "ribbons", "hills", "arcs"].contains(recipe.style) { result.style = "mesh" }
        let valid = { (hex: String) in HexColor.parse(hex) != nil }
        var background = recipe.background.filter(valid)
        if background.isEmpty { background = dark ? ["#141a33", "#1f2547"] : ["#f6f2ff", "#eef4ff"] }
        if background.count == 1 { background.append(background[0]) }
        result.background = Array(background.prefix(2))
        var colors = recipe.colors.filter(valid)
        if colors.count < 2 { colors += dark ? ["#3b4ba8", "#7a4fd8"] : ["#c8d8ff", "#e6c8ff"] }
        result.colors = Array(colors.prefix(6))
        if result.name.trimmingCharacters(in: .whitespaces).isEmpty { result.name = "My Wallpaper" }
        return result
    }
}

enum HexColor {
    /// "#RRGGBB" (or without "#") to RGB components 0…1.
    static func parse(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        return (CGFloat((value >> 16) & 0xff) / 255, CGFloat((value >> 8) & 0xff) / 255, CGFloat(value & 0xff) / 255)
    }

    static func cgColor(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let c = parse(hex) ?? (0.5, 0.5, 0.5)
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    static func mix(_ a: String, _ b: String, _ t: CGFloat) -> CGColor {
        let x = parse(a) ?? (0.5, 0.5, 0.5)
        let y = parse(b) ?? (0.5, 0.5, 0.5)
        return CGColor(srgbRed: x.r + (y.r - x.r) * t, green: x.g + (y.g - x.g) * t, blue: x.b + (y.b - x.b) * t, alpha: 1)
    }
}

/// Paints a recipe with Core Graphics, in the same families of styles as the built-in library.
enum WallpaperPainter {
    static func render(_ recipe: WallpaperRecipe, size: CGSize) -> CGImage? {
        let width = max(Int(size.width), 16)
        let height = max(Int(size.height), 16)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Work in top-left coordinates, like the design descriptions.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let w = CGFloat(width)
        let h = CGFloat(height)
        var random = SeededRandom(seed: stableHash(recipe.name + recipe.style))
        let dark = recipe.theme == "dark"

        // Background
        let background = recipe.background.map { HexColor.cgColor($0) } as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: background, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }

        switch recipe.style {
        case "waves":
            paintBands(context, recipe.colors, w: w, h: h, start: 0.38, amplitude: 0.045, frequency: 1.1,
                       shadow: dark ? 0.35 : 0.14, random: &random)
        case "hills":
            paintBands(context, recipe.colors, w: w, h: h, start: 0.5, amplitude: 0.07, frequency: 0.6,
                       shadow: dark ? 0.3 : 0.1, random: &random)
        case "ribbons":
            paintRibbons(context, recipe.colors, w: w, h: h, random: &random)
        case "arcs":
            paintArcs(context, recipe.colors, w: w, h: h, random: &random)
        default:
            paintMesh(context, recipe.colors, space: space, w: w, h: h, dark: dark, random: &random)
        }
        return context.makeImage()
    }

    private static func paintMesh(_ context: CGContext, _ colors: [String], space: CGColorSpace,
                                  w: CGFloat, h: CGFloat, dark: Bool, random: inout SeededRandom) {
        for (index, hex) in colors.enumerated() {
            let center = CGPoint(x: w * random.next(0.1, 0.9),
                                 y: h * (index.isMultiple(of: 2) ? random.next(0.1, 0.5) : random.next(0.5, 0.95)))
            let radius = max(w, h) * random.next(0.28, 0.42)
            let strength: CGFloat = dark ? 0.75 : 0.9
            let stops = [HexColor.cgColor(hex, alpha: strength), HexColor.cgColor(hex, alpha: strength * 0.45),
                         HexColor.cgColor(hex, alpha: 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.45, 1]) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: radius, options: [])
            }
        }
    }

    private static func paintBands(_ context: CGContext, _ colors: [String], w: CGFloat, h: CGFloat,
                                   start: CGFloat, amplitude: CGFloat, frequency: CGFloat, shadow: CGFloat,
                                   random: inout SeededRandom) {
        let spread = (0.92 - start) / CGFloat(max(colors.count, 1))
        for (index, hex) in colors.enumerated() {
            let phase = random.next(0, .pi * 2)
            let y0 = h * (start + CGFloat(index) * spread)
            let path = CGMutablePath()
            let steps = 240
            for step in 0...steps {
                let x = w * CGFloat(step) / CGFloat(steps)
                let u = CGFloat(step) / CGFloat(steps)
                let y = y0 + h * amplitude * sin(u * .pi * 2 * frequency + phase)
                    + h * amplitude * 0.45 * sin(u * .pi * 2 * frequency * 2.3 + phase * 1.7)
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()

            context.saveGState()
            // Shadow cast onto the band behind gives a paper-cut depth.
            context.setShadow(offset: CGSize(width: 0, height: h * 0.004), blur: h * 0.014,
                              color: CGColor(gray: 0, alpha: shadow))
            context.addPath(path)
            context.setFillColor(HexColor.cgColor(hex))
            context.fillPath()
            context.restoreGState()
        }
    }

    private static func paintRibbons(_ context: CGContext, _ colors: [String], w: CGFloat, h: CGFloat,
                                     random: inout SeededRandom) {
        for (index, hex) in colors.prefix(3).enumerated() {
            let phase = random.next(0, .pi * 2)
            let y0 = h * (0.38 + CGFloat(index) * 0.14)
            let amplitude = h * random.next(0.08, 0.14)
            let path = CGMutablePath()
            for step in 0...200 {
                let u = CGFloat(step) / 200
                let y = y0 + amplitude * sin(u * .pi * 1.6 + phase) + amplitude * 0.3 * sin(u * .pi * 3.8)
                if step == 0 { path.move(to: CGPoint(x: 0, y: y)) } else { path.addLine(to: CGPoint(x: w * u, y: y)) }
            }
            let width = h * (0.05 - CGFloat(index) * 0.012)
            context.saveGState()
            context.setLineCap(.round)
            context.setShadow(offset: .zero, blur: h * 0.05, color: HexColor.cgColor(hex, alpha: 0.8))
            context.setStrokeColor(HexColor.cgColor(hex))
            context.setLineWidth(width)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
            // Highlight along the top of the ribbon.
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
            context.setLineWidth(width * 0.25)
            context.translateBy(x: 0, y: -width * 0.2)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

    private static func paintArcs(_ context: CGContext, _ colors: [String], w: CGFloat, h: CGFloat,
                                  random: inout SeededRandom) {
        let fromBottomLeft = random.next(0, 1) < 0.5
        let center = fromBottomLeft ? CGPoint(x: -w * 0.03, y: h * 1.08) : CGPoint(x: w * 1.03, y: -h * 0.08)
        let rings = 9
        let maxRadius = hypot(w, h) * 1.05
        // Outermost ring first, smaller rings on top.
        for ring in stride(from: rings, through: 1, by: -1) {
            let t = CGFloat(ring - 1) / CGFloat(rings - 1)
            let position = t * CGFloat(colors.count - 1)
            let index = min(Int(position), colors.count - 2)
            let color = HexColor.mix(colors[index], colors[index + 1], position - CGFloat(index))
            let radius = maxRadius * CGFloat(ring) / CGFloat(rings)
            context.saveGState()
            context.setShadow(offset: .zero, blur: h * 0.01, color: CGColor(gray: 0, alpha: 0.12))
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.restoreGState()
        }
    }

    /// FNV-1a: stable across launches, unlike `hashValue`.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed | 1
    }

    mutating func next(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = CGFloat(state >> 11) / CGFloat(UInt64(1) << 53)
        return low + (high - low) * unit
    }
}
