import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum WallpaperTheme: String, Codable, CaseIterable {
    case light
    case dark
}

/// What the gallery shows: light wallpapers, dark wallpapers, or every wallpaper with a glass finish.
enum WallpaperFinish: String, CaseIterable, Identifiable {
    case light
    case dark
    case glassy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .glassy: "Glassy"
        }
    }
}

struct WallpaperItem: Identifiable, Hashable, Codable {
    enum Source: String, Codable {
        case builtIn
        case custom
        case generated
    }

    var id: String
    var name: String
    var theme: WallpaperTheme
    var source: Source
    /// Full-size image. Relative to the built-in folder for built-in items, absolute otherwise.
    var file: String
    var thumb: String
}

/// The wallpaper library: 30 built-in wallpapers, images the user adds, and ones designed
/// with Claude. Choosing one sets the real macOS desktop picture (optionally with a glass finish).
@MainActor
final class WallpaperLibrary: ObservableObject {
    @Published private(set) var builtIn: [WallpaperItem] = []
    @Published private(set) var mine: [WallpaperItem] = []
    @Published var finish: WallpaperFinish {
        didSet { defaults.set(finish.rawValue, forKey: Key.finish) }
    }
    @Published private(set) var currentID: String?
    @Published private(set) var currentGlassy = false
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    @Published private(set) var hasAPIKey = Keychain.read(WallpaperDesigner.keychainAccount) != nil

    private enum Key {
        static let finish = "wallpaper.finish"
        static let currentID = "wallpaper.currentID"
        static let currentGlassy = "wallpaper.currentGlassy"
    }

    private let defaults: UserDefaults
    let builtInRoot: URL?
    let storeRoot: URL
    private var thumbnailCache: [String: NSImage] = [:]

    init(defaults: UserDefaults = .standard, storeRoot: URL? = nil, builtInRoot: URL? = WallpaperLibrary.findBuiltInRoot()) {
        self.defaults = defaults
        self.builtInRoot = builtInRoot
        self.storeRoot = storeRoot ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland/Wallpapers", isDirectory: true)
        finish = WallpaperFinish(rawValue: defaults.string(forKey: Key.finish) ?? "") ?? .light
        currentID = defaults.string(forKey: Key.currentID)
        currentGlassy = defaults.bool(forKey: Key.currentGlassy)
        builtIn = Self.loadCatalog(root: builtInRoot)
        mine = loadMine()
    }

    // MARK: - Listing

    var visibleItems: [WallpaperItem] {
        let all = mine + builtIn
        switch finish {
        case .light: return all.filter { $0.theme == .light }
        case .dark: return all.filter { $0.theme == .dark }
        case .glassy: return all
        }
    }

    func fileURL(_ item: WallpaperItem) -> URL? {
        if item.source == .builtIn {
            return builtInRoot?.appendingPathComponent(item.file)
        }
        return URL(fileURLWithPath: item.file)
    }

    func thumbnail(for item: WallpaperItem, glassy: Bool) -> NSImage? {
        let key = "\(item.id)|\(glassy)"
        if let cached = thumbnailCache[key] { return cached }
        let url = item.source == .builtIn
            ? builtInRoot?.appendingPathComponent(item.thumb)
            : URL(fileURLWithPath: item.thumb)
        guard let url, var image = CIImage(contentsOf: url) else { return nil }
        if glassy { image = GlassFinish.apply(to: image) }
        guard let cgImage = GlassFinish.context.createCGImage(image, from: image.extent) else { return nil }
        let result = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache[key] = result
        return result
    }

    // MARK: - Applying

    /// Sets the desktop picture on every screen.
    func apply(_ item: WallpaperItem, glassy: Bool) {
        guard !isWorking, let source = fileURL(item) else { return }
        isWorking = true
        message = nil
        let renderedFolder = storeRoot.appendingPathComponent("Rendered", isDirectory: true)
        Task {
            let id = item.id
            let result: URL?
            if glassy {
                result = await Task.detached(priority: .userInitiated) {
                    try? WallpaperLibrary.renderGlass(source: source, id: id, folder: renderedFolder)
                }.value
            } else {
                result = source
            }
            isWorking = false
            guard let url = result else {
                message = "Couldn't make the glass version of \(item.name)."
                return
            }
            do {
                try Self.setDesktopPicture(url)
                currentID = item.id
                currentGlassy = glassy
                defaults.set(item.id, forKey: Key.currentID)
                defaults.set(glassy, forKey: Key.currentGlassy)
                message = "\(item.name)\(glassy ? " (glass)" : "") is now your wallpaper."
            } catch {
                message = "Couldn't set the wallpaper: \(error.localizedDescription)"
            }
        }
    }

    static func setDesktopPicture(_ url: URL) throws {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ]
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    /// Writes the glass version once and reuses it. The file name changes with the source
    /// so macOS doesn't keep showing an old cached picture.
    nonisolated static func renderGlass(source: URL, id: String, folder: URL) throws -> URL {
        let modified = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let target = folder.appendingPathComponent("\(id)-glass-\(Int(modified)).jpg")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let input = CIImage(contentsOf: source) else { throw CocoaError(.fileReadCorruptFile) }
        let output = GlassFinish.apply(to: input)
        guard let image = GlassFinish.context.createCGImage(output, from: output.extent) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try writeJPEG(image, to: target)
        return target
    }

    // MARK: - Your own wallpapers

    func importImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Library"
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { self?.add(urls) }
        }
    }

    func add(_ urls: [URL]) {
        var added = 0
        for url in urls {
            if let item = try? storeImage(at: url, source: .custom, name: url.deletingPathExtension().lastPathComponent) {
                mine.insert(item, at: 0)
                added += 1
            }
        }
        saveMine()
        message = added == 0 ? "Those files couldn't be added." : (added == 1 ? "Added 1 wallpaper." : "Added \(added) wallpapers.")
        if added > 0, finish != .glassy, let first = mine.first { finish = first.theme == .dark ? .dark : .light }
    }

    /// Removes your own wallpaper from the library and deletes NotchIsland's copy.
    /// The original file you added is never touched.
    func remove(_ item: WallpaperItem) {
        guard item.source != .builtIn else { return }
        try? FileManager.default.removeItem(atPath: item.file)
        try? FileManager.default.removeItem(atPath: item.thumb)
        mine.removeAll { $0.id == item.id }
        saveMine()
    }

    private func storeImage(at url: URL, source: WallpaperItem.Source, name: String) throws -> WallpaperItem {
        let id = UUID().uuidString
        let folder = storeRoot.appendingPathComponent(source == .generated ? "Generated" : "Custom", isDirectory: true)
        let thumbs = storeRoot.appendingPathComponent("Thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)

        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        let file = folder.appendingPathComponent("\(id).\(ext)")
        try FileManager.default.copyItem(at: url, to: file)

        let thumbURL = thumbs.appendingPathComponent("\(id).jpg")
        guard let thumb = Self.makeThumbnail(file) else { throw CocoaError(.fileReadCorruptFile) }
        try Self.writeJPEG(thumb, to: thumbURL, quality: 0.85)

        return WallpaperItem(id: id, name: name, theme: Self.theme(of: thumb), source: source,
                             file: file.path, thumb: thumbURL.path)
    }

    // MARK: - Designed with Claude

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasAPIKey = Keychain.save(trimmed, account: WallpaperDesigner.keychainAccount)
        message = hasAPIKey ? "API key saved in your keychain." : "Couldn't save the key."
    }

    func removeAPIKey() {
        Keychain.delete(WallpaperDesigner.keychainAccount)
        hasAPIKey = false
    }

    /// Asks Claude for a design, paints it at your screen's resolution, adds it and sets it.
    func generate(prompt: String) {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isWorking else { return }
        guard let key = Keychain.read(WallpaperDesigner.keychainAccount) else {
            message = WallpaperDesignerError.missingKey.errorDescription
            return
        }
        isWorking = true
        message = "Designing…"
        let size = Self.screenPixelSize()
        Task {
            do {
                let recipe = try await WallpaperDesigner.design(prompt: request, apiKey: key)
                guard let image = WallpaperPainter.render(recipe, size: size) else {
                    throw WallpaperDesignerError.badResponse
                }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
                try Self.writeJPEG(image, to: temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                var item = try storeImage(at: temporary, source: .generated, name: recipe.name)
                item.theme = recipe.theme == "dark" ? .dark : .light
                mine.insert(item, at: 0)
                saveMine()
                isWorking = false
                message = "Made \"\(recipe.name)\": \(recipe.description)"
                if finish != .glassy { finish = item.theme == .dark ? .dark : .light }
                apply(item, glassy: finish == .glassy)
            } catch {
                isWorking = false
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Storage

    private var mineIndex: URL { storeRoot.appendingPathComponent("library.json") }

    private func loadMine() -> [WallpaperItem] {
        guard let data = try? Data(contentsOf: mineIndex),
              let items = try? JSONDecoder().decode([WallpaperItem].self, from: data)
        else { return [] }
        return items.filter { FileManager.default.fileExists(atPath: $0.file) }
    }

    private func saveMine() {
        try? FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(mine) {
            try? data.write(to: mineIndex, options: .atomic)
        }
    }

    // MARK: - Helpers

    /// Built-in wallpapers live in the app's Resources, or in Packaging/ when run from source.
    nonisolated static func findBuiltInRoot() -> URL? {
        let fileManager = FileManager.default
        if let resources = Bundle.main.resourceURL?.appendingPathComponent("Wallpapers"),
           fileManager.fileExists(atPath: resources.appendingPathComponent("catalog.json").path) {
            return resources
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Services
            .deletingLastPathComponent()   // NotchIsland
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repository root
        let source = repository.appendingPathComponent("Packaging/Wallpapers")
        return fileManager.fileExists(atPath: source.appendingPathComponent("catalog.json").path) ? source : nil
    }

    nonisolated static func loadCatalog(root: URL?) -> [WallpaperItem] {
        struct Entry: Decodable {
            let id, name, theme, file, thumb: String
        }
        guard let root,
              let data = try? Data(contentsOf: root.appendingPathComponent("catalog.json")),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.map {
            WallpaperItem(id: $0.id, name: $0.name, theme: WallpaperTheme(rawValue: $0.theme) ?? .light,
                          source: .builtIn, file: $0.file, thumb: $0.thumb)
        }
    }

    nonisolated static func makeThumbnail(_ url: URL, maxPixels: Int = 432) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated static func theme(of image: CGImage) -> WallpaperTheme {
        GlassFinish.averageLuminance(of: CIImage(cgImage: image)) < 0.45 ? .dark : .light
    }

    nonisolated static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.9) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Size in pixels of the main screen, for painting designs at full sharpness.
    static func screenPixelSize() -> CGSize {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return CGSize(width: 3456, height: 2234) }
        let scale = screen.backingScaleFactor
        return CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
    }
}
