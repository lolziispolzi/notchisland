import AppKit
import Combine

/// A folder files can be copied to from the drop zone.
struct DropDestination: Identifiable, Hashable {
    let name: String
    let url: URL
    let symbol: String

    var id: String { url.path }
}

/// The drop zone: files dropped on the island wait here until they are copied,
/// moved, shared, AirDropped or dragged out. Stores references, not copies.
@MainActor
final class ShelfStore: ObservableObject {
    private static let key = "shelf.items"

    @Published private(set) var items: [URL] = [] {
        didSet { defaults.set(items.map(\.path), forKey: Self.key) }
    }
    @Published private(set) var destinations: [DropDestination] = []
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?

    private let settings: AppSettings
    private let defaults: UserDefaults
    private var statusWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: Self.key) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }

        settings.$customDropFolders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshDestinations() }
            .store(in: &cancellables)
    }

    // MARK: - Items

    func add(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.add(url) }
                }
            }
        }
    }

    func add(_ url: URL) {
        let url = url.standardizedFileURL
        guard !items.contains(url) else { return }
        items.append(url)
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
    }

    /// Lets you pick files to add, for when dragging isn't convenient.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Drop Zone"
        NSApp.activateCompat()
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { urls.forEach { self?.add($0) } }
        }
    }

    func clear() {
        items.removeAll()
    }

    // MARK: - Destinations

    func refreshDestinations() {
        let custom = settings.customDropFolders.map { path in
            DropDestination(name: URL(fileURLWithPath: path).lastPathComponent,
                            url: URL(fileURLWithPath: path),
                            symbol: "folder")
        }
        destinations = Self.detectedDestinations() + custom
    }

    /// Common folders plus cloud drives found on this Mac (iCloud Drive, Dropbox,
    /// Google Drive, OneDrive). Cloud apps sync whatever is copied into their folder.
    nonisolated static func detectedDestinations(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [DropDestination] {
        var result: [DropDestination] = []

        func add(_ name: String, _ url: URL, _ symbol: String) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  !result.contains(where: { $0.name == name })
            else { return }
            result.append(DropDestination(name: name, url: url, symbol: symbol))
        }

        add("Desktop", home.appendingPathComponent("Desktop"), "menubar.dock.rectangle")
        add("Downloads", home.appendingPathComponent("Downloads"), "arrow.down.circle")
        add("Documents", home.appendingPathComponent("Documents"), "doc")
        add("iCloud Drive", home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), "icloud")

        let cloudStorage = home.appendingPathComponent("Library/CloudStorage")
        let providers = (try? fileManager.contentsOfDirectory(atPath: cloudStorage.path)) ?? []
        for name in providers.sorted() {
            let url = cloudStorage.appendingPathComponent(name)
            if name.hasPrefix("Dropbox") {
                add("Dropbox", url, "shippingbox")
            } else if name.hasPrefix("GoogleDrive") {
                let myDrive = url.appendingPathComponent("My Drive")
                add("Google Drive", fileManager.fileExists(atPath: myDrive.path) ? myDrive : url, "externaldrive")
            } else if name.hasPrefix("OneDrive") {
                add("OneDrive", url, "cloud")
            }
        }
        // Older Dropbox installs.
        add("Dropbox", home.appendingPathComponent("Dropbox"), "shippingbox")
        return result
    }

    // MARK: - Actions

    /// Copies (or moves) files into a folder. Defaults to every item on the shelf.
    func copy(_ urls: [URL]? = nil, to folder: URL, move: Bool = false) {
        let sources = urls ?? items
        guard !sources.isEmpty, !isBusy else { return }
        isBusy = true
        let removeAfter = move || settings.removeAfterCopy

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ShelfStore.transfer(sources, to: folder, move: move)
            }.value
            isBusy = false
            if removeAfter {
                items.removeAll { result.succeeded.contains($0) }
            }
            if result.failed.isEmpty {
                let verb = move ? "Moved" : "Copied"
                showStatus("\(verb) \(Self.countLabel(result.succeeded.count)) to \(folder.lastPathComponent)")
            } else {
                showStatus("\(Self.countLabel(result.failed.count)) could not be copied")
            }
        }
    }

    /// Asks for a folder, then copies or moves every item there.
    func chooseFolder(move: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = move ? "Move Here" : "Copy Here"
        NSApp.activateCompat()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.copy(to: url, move: move) }
        }
    }

    func copyToClipboard() {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items as [NSURL])
        showStatus("Copied \(Self.countLabel(items.count)) to the clipboard")
    }

    func airDropAll() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activateCompat()
        service.perform(withItems: items)
    }

    private func showStatus(_ message: String) {
        statusWork?.cancel()
        statusMessage = message
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.statusMessage = nil }
        }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: - File operations (off the main thread)

    nonisolated static func transfer(_ sources: [URL], to folder: URL, move: Bool) -> (succeeded: [URL], failed: [URL]) {
        let fileManager = FileManager.default
        var succeeded: [URL] = []
        var failed: [URL] = []
        for source in sources {
            let target = uniqueDestination(for: source, in: folder, fileManager: fileManager)
            do {
                if move {
                    try fileManager.moveItem(at: source, to: target)
                } else {
                    try fileManager.copyItem(at: source, to: target)
                }
                succeeded.append(source)
            } catch {
                failed.append(source)
            }
        }
        return (succeeded, failed)
    }

    /// "report.pdf" becomes "report 2.pdf", "report 3.pdf", … if the name is taken.
    nonisolated static func uniqueDestination(for source: URL, in folder: URL, fileManager: FileManager = .default) -> URL {
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = folder.appendingPathComponent(name)
            number += 1
        }
        return candidate
    }

    nonisolated static func countLabel(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}
