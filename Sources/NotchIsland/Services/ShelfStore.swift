import AppKit

/// Files dropped on the island. Stores references to the files, not copies.
@MainActor
final class ShelfStore: ObservableObject {
    private static let key = "shelf.items"

    @Published private(set) var items: [URL] = [] {
        didSet { defaults.set(items.map(\.path), forKey: Self.key) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: Self.key) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

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

    func clear() {
        items.removeAll()
    }

    func airDropAll() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: items)
    }
}
