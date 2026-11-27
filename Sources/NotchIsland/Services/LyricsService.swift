import Combine
import Foundation

struct LyricLine: Equatable, Identifiable {
    let id: Int
    /// Seconds from the start of the song.
    let time: Double
    /// Empty for an instrumental break.
    let text: String
}

struct Lyrics: Equatable {
    /// Time-synced lines. Empty when only plain lyrics exist.
    var synced: [LyricLine]
    var plain: [String]
    var instrumental: Bool

    var isSynced: Bool { !synced.isEmpty }
}

/// Parser for LRC, the common synced-lyrics format: "[01:23.45] line of text".
enum LRC {
    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)

    static func parse(_ text: String) -> [LyricLine] {
        var offset = 0.0
        var entries: [(time: Double, text: String)] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("[offset:") {
                let digits = line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)
                offset = (Double(digits) ?? 0) / 1000
                continue
            }

            let ns = line as NSString
            let matches = timeTag.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let lyric = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard let minutes = Double(ns.substring(with: match.range(at: 1))),
                      let seconds = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ":", with: "."))
                else { continue }
                entries.append((minutes * 60 + seconds, lyric))
            }
        }

        // A positive LRC offset means the lyrics should appear earlier.
        return entries
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: max(0, $0.element.time - offset), text: $0.element.text) }
    }

    /// Index of the line being sung at `time`, or nil before the first line.
    static func index(at time: Double, in lines: [LyricLine]) -> Int? {
        guard let first = lines.first, time >= first.time else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

/// LRCLIB: free, open lyrics database with synced lyrics. No key needed. https://lrclib.net
enum LRCLIB {
    struct Record: Decodable, Equatable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    enum Result: Equatable {
        case found(Lyrics)
        case notFound
        case failed
    }

    /// LRCLIB asks clients to identify themselves.
    static let userAgent = "NotchIsland/0.1 (open-source macOS notch app)"
    private static let base = "https://lrclib.net/api/"

    static func getURL(for track: Track) -> URL {
        var components = URLComponents(string: base + "get")!
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        components.queryItems = items
        return components.url!
    }

    static func searchURL(title: String, artist: String) -> URL {
        var components = URLComponents(string: base + "search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        return components.url!
    }

    /// "Song - Remastered 2011" and "Song (feat. X)" become "Song", for a looser search.
    static func cleanTitle(_ title: String) -> String {
        var result = title
        if let dash = result.range(of: " - ") {
            result = String(result[..<dash.lowerBound])
        }
        result = result.replacingOccurrences(of: #"\s*[\(\[](feat\.?|ft\.?|with|remaster|live|radio edit)[^\)\]]*[\)\]]"#,
                                              with: "",
                                              options: [.regularExpression, .caseInsensitive])
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// "Artist A, Artist B" becomes "Artist A".
    static func primaryArtist(_ artist: String) -> String {
        let separators = [", ", " & ", " feat. ", " x "]
        var result = artist
        for separator in separators {
            if let range = result.range(of: separator) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func lyrics(from record: Record) -> Lyrics? {
        let synced = LRC.parse(record.syncedLyrics ?? "")
        let plain = (record.plainLyrics ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let hasPlain = plain.contains { !$0.isEmpty }
        let instrumental = record.instrumental ?? false
        guard !synced.isEmpty || hasPlain || instrumental else { return nil }
        return Lyrics(synced: synced, plain: hasPlain ? plain : [], instrumental: instrumental)
    }

    /// Prefers synced lyrics whose duration matches the song.
    static func best(_ records: [Record], duration: Double) -> Record? {
        func durationMatches(_ record: Record, within seconds: Double) -> Bool {
            guard duration > 0, let other = record.duration else { return true }
            return abs(other - duration) <= seconds
        }
        let synced = records.filter { !($0.syncedLyrics ?? "").isEmpty }
        return synced.first { durationMatches($0, within: 3) }
            ?? synced.first { durationMatches($0, within: 10) }
            ?? records.first { !($0.plainLyrics ?? "").isEmpty && durationMatches($0, within: 10) }
    }

    static func fetch(for track: Track) async -> Result {
        do {
            if let record = try await request(getURL(for: track), as: Record.self),
               let lyrics = lyrics(from: record) {
                return .found(lyrics)
            }
            let url = searchURL(title: cleanTitle(track.title), artist: primaryArtist(track.artist))
            let records = try await request(url, as: [Record].self) ?? []
            if let record = best(records, duration: track.duration), let lyrics = lyrics(from: record) {
                return .found(lyrics)
            }
            return .notFound
        } catch {
            return .failed
        }
    }

    /// Returns nil for 404 (no lyrics), throws for other failures.
    private static func request<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.compatData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Finds lyrics for the current song and tracks which line is being sung.
@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var notFound = false

    private let settings: AppSettings
    private let nowPlaying: NowPlayingService
    private var cache: [String: Lyrics] = [:]
    private var missing: Set<String> = []
    private var currentKey: String?
    private var loadTask: Task<Void, Never>?
    private var resyncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, nowPlaying: NowPlayingService) {
        self.settings = settings
        self.nowPlaying = nowPlaying

        nowPlaying.$track
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in self?.load(for: track) }
            .store(in: &cancellables)

        settings.$lyricsEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.currentKey = nil
                self?.load(for: self?.nowPlaying.track)
            }
            .store(in: &cancellables)

        nowPlaying.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateResync() }
            .store(in: &cancellables)
    }

    /// Index of the line being sung now, after the user's timing offset.
    func currentIndex(at elapsed: Double) -> Int? {
        guard let lines = lyrics?.synced, !lines.isEmpty else { return nil }
        return LRC.index(at: elapsed + settings.lyricsOffset, in: lines)
    }

    func currentLine(at elapsed: Double) -> LyricLine? {
        guard let index = currentIndex(at: elapsed) else { return nil }
        return lyrics?.synced[index]
    }

    func retry() {
        currentKey = nil
        load(for: nowPlaying.track)
    }

    private func load(for track: Track?) {
        loadTask?.cancel()
        guard settings.lyricsEnabled, let track, !track.title.isEmpty else {
            currentKey = nil
            lyrics = nil
            notFound = false
            state = .idle
            updateResync()
            return
        }

        let key = "\(track.title)|\(track.artist)|\(track.album)"
        guard key != currentKey else { return }
        currentKey = key
        lyrics = cache[key]
        notFound = missing.contains(key)
        if lyrics != nil || notFound {
            state = .idle
            updateResync()
            return
        }

        state = .loading
        loadTask = Task {
            let result = await LRCLIB.fetch(for: track)
            guard !Task.isCancelled, currentKey == key else { return }
            switch result {
            case .found(let found):
                if cache.count > 200 { cache.removeAll() }
                cache[key] = found
                lyrics = found
                state = .idle
            case .notFound:
                missing.insert(key)
                notFound = true
                state = .idle
            case .failed:
                state = .failed("Couldn't load lyrics.")
            }
            updateResync()
        }
    }

    /// While synced lyrics play, re-read the player position every 15 seconds,
    /// so seeks made in the player app don't leave the lyrics out of sync.
    private func updateResync() {
        resyncTimer?.invalidate()
        resyncTimer = nil
        guard lyrics?.isSynced == true, nowPlaying.isPlaying else { return }
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.nowPlaying.refreshPosition() }
        }
    }
}
