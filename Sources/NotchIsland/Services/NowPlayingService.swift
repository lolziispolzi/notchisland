import AppKit

enum MediaPlayer: String, CaseIterable {
    case music
    case spotify

    var appName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Distributed notification the player posts on every state or track change.
    var notificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    /// Only script a player that is running. Scripting a closed app launches it,
    /// and scripting a missing app shows a "Where is…?" dialog.
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: Double
}

/// One parsed state change from a player.
struct PlaybackUpdate: Equatable {
    enum State: Equatable {
        case playing, paused, stopped
    }

    var state: State
    var track: Track?
    /// Seconds, when known.
    var position: Double?

    static let stopped = PlaybackUpdate(state: .stopped, track: nil, position: nil)

    static func state(from string: String) -> State {
        switch string.lowercased() {
        case "playing": .playing
        case "paused": .paused
        default: .stopped
        }
    }

    /// Parses the userInfo of a Music or Spotify distributed notification.
    static func from(userInfo: [AnyHashable: Any], player: MediaPlayer) -> PlaybackUpdate {
        let state = state(from: userInfo["Player State"] as? String ?? "")
        guard state != .stopped, let title = userInfo["Name"] as? String else { return .stopped }

        let durationKey = player == .music ? "Total Time" : "Duration"
        let durationMs = (userInfo[durationKey] as? NSNumber)?.doubleValue ?? 0
        let track = Track(title: title,
                          artist: userInfo["Artist"] as? String ?? "",
                          album: userInfo["Album"] as? String ?? "",
                          duration: durationMs / 1000)
        let position = (userInfo["Playback Position"] as? NSNumber)?.doubleValue
        return PlaybackUpdate(state: state, track: track, position: position)
    }

    /// Parses the output of `NowPlayingService.statusScript(for:)`.
    static func from(scriptOutput: String, player: MediaPlayer) -> PlaybackUpdate? {
        let lines = scriptOutput.components(separatedBy: .newlines)
        if lines.first?.lowercased() == "stopped" { return .stopped }
        guard lines.count >= 6 else { return nil }

        let state = state(from: lines[0])
        // Music reports duration in seconds, Spotify in milliseconds.
        let rawDuration = number(lines[4]) ?? 0
        let duration = player == .spotify ? rawDuration / 1000 : rawDuration
        let track = Track(title: lines[1], artist: lines[2], album: lines[3], duration: duration)
        return PlaybackUpdate(state: state, track: track, position: number(lines[5]))
    }

    /// Parses the output of `NowPlayingService.modesScript(for:)`: two lines, "true"/"false".
    static func modes(from output: String) -> (shuffle: Bool, repeating: Bool)? {
        let lines = output.lowercased().components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2,
              ["true", "false"].contains(lines[0]),
              ["true", "false"].contains(lines[1])
        else { return nil }
        return (lines[0] == "true", lines[1] == "true")
    }

    /// Parses an AppleScript number, which may use a comma as decimal separator.
    static func number(_ string: String) -> Double? {
        Double(string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

/// Tracks what Music or Spotify is playing and controls playback.
///
/// State comes from the players' distributed notifications, so nothing polls.
/// AppleScript is used only for artwork, the playback position, and controls.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var player: MediaPlayer?
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// Strong colors from the artwork, for tinted backgrounds.
    @Published private(set) var palette: [NSColor] = []
    @Published private(set) var shuffle = false
    @Published private(set) var repeating = false

    private var position: Double = 0
    private var positionDate = Date()
    private var artworkKey: String?
    private var observers: [NSObjectProtocol] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        for player in MediaPlayer.allCases {
            let token = distributed.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                let update = PlaybackUpdate.from(userInfo: note.userInfo ?? [:], player: player)
                MainActor.assumeIsolated { self?.handle(update, from: player) }
            }
            observers.append(token)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let token = workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let player = self.player, player.bundleID == bundleID else { return }
                self.clear()
            }
        }
        observers.append(token)

        refresh()
    }

    /// Elapsed seconds, extrapolated from the last known position.
    func elapsed(at date: Date) -> Double {
        guard let track else { return 0 }
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        let clamped = max(value, 0)
        return track.duration > 0 ? min(clamped, track.duration) : clamped
    }

    // MARK: - Controls

    func playPause() {
        send("playpause")
        let now = elapsed(at: Date())
        isPlaying.toggle()
        setPosition(now)
    }

    func next() { send("next track") }

    func previous() { send("previous track") }

    func toggleShuffle() {
        guard let player else { return }
        send(player == .spotify ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled")
        shuffle.toggle()
    }

    func toggleRepeat() {
        guard let player else { return }
        send(player == .spotify
             ? "set repeating to not repeating"
             : "if song repeat is off then set song repeat to all else set song repeat to off")
        repeating.toggle()
    }

    func seek(to seconds: Double) {
        let target = max(0, seconds)
        // String(format:) always uses "." as decimal separator, which AppleScript expects.
        send("set player position to \(String(format: "%.1f", target))")
        setPosition(target)
    }

    /// Brings the current player (or Spotify) to the front.
    func openPlayer() {
        let bundleID = (player ?? .spotify).bundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard let player, player.isRunning else { return }
        Task { _ = await AppleScript.run("tell application \"\(player.appName)\" to \(command)") }
    }

    // MARK: - Refresh

    /// Reads current state from running players. Used at launch.
    func refresh() {
        Task {
            for candidate in MediaPlayer.allCases where candidate.isRunning {
                guard let output = await AppleScript.run(Self.statusScript(for: candidate)),
                      let update = PlaybackUpdate.from(scriptOutput: output, player: candidate)
                else { continue }
                if update.state == .playing || player == nil {
                    handle(update, from: candidate)
                }
                if update.state == .playing { break }
            }
        }
    }

    /// Re-syncs the playback position. Called when the island opens.
    func refreshPosition() {
        guard let player, player.isRunning else { return }
        Task {
            let script = "tell application \"\(player.appName)\" to return ((player position) as string)"
            guard let output = await AppleScript.run(script),
                  let value = PlaybackUpdate.number(output),
                  self.player == player
            else { return }
            setPosition(value)
        }
    }

    /// Reads shuffle and repeat state. Called on open and on track change.
    func refreshModes() {
        guard let player, player.isRunning else { return }
        Task {
            guard let output = await AppleScript.run(Self.modesScript(for: player)),
                  let modes = PlaybackUpdate.modes(from: output),
                  self.player == player
            else { return }
            shuffle = modes.shuffle
            repeating = modes.repeating
        }
    }

    // MARK: - State

    private func handle(_ update: PlaybackUpdate, from source: MediaPlayer) {
        // Another player paused or stopped while the current one plays: ignore it.
        if source != player, update.state != .playing, isPlaying { return }

        switch update.state {
        case .stopped:
            if source == player || player == nil { clear() }
        case .playing, .paused:
            let current = elapsed(at: Date())
            player = source
            if let newTrack = update.track, newTrack != track {
                track = newTrack
                setPosition(0)
                loadArtwork(for: source, track: newTrack)
                refreshModes()
            } else {
                setPosition(current)
            }
            isPlaying = update.state == .playing
            if let position = update.position {
                setPosition(position)
            } else {
                refreshPosition()
            }
        }
    }

    private func setPosition(_ value: Double) {
        position = value
        positionDate = Date()
    }

    private func clear() {
        player = nil
        track = nil
        isPlaying = false
        artwork = nil
        palette = []
        artworkKey = nil
        setPosition(0)
    }

    // MARK: - Artwork

    private func loadArtwork(for player: MediaPlayer, track: Track) {
        let key = "\(player.rawValue)|\(track.title)|\(track.artist)|\(track.album)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        Task {
            let image = await Self.fetchArtwork(for: player)
            guard self.artworkKey == key else { return }
            self.artwork = image
            self.palette = image.map(ArtworkPalette.colors(from:)) ?? []
        }
    }

    private static func fetchArtwork(for player: MediaPlayer) async -> NSImage? {
        switch player {
        case .music:
            guard let path = await AppleScript.run(musicArtworkScript), !path.isEmpty else { return nil }
            return NSImage(contentsOfFile: path)
        case .spotify:
            guard let string = await AppleScript.run(spotifyArtworkScript),
                  let url = URL(string: string), url.scheme == "https",
                  let result = try? await URLSession.shared.data(from: url)
            else { return nil }
            return NSImage(data: result.0)
        }
    }

    // MARK: - Scripts

    static func statusScript(for player: MediaPlayer) -> String {
        """
        tell application "\(player.appName)"
            if player state is stopped then return "stopped"
            set t to current track
            return ((player state) as string) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & ((player position) as string)
        end tell
        """
    }

    /// Writes the current Music artwork to a temp file and returns its path.
    static let musicArtworkScript = """
    tell application "Music"
        if (count of artworks of current track) is 0 then return ""
        set artData to raw data of artwork 1 of current track
    end tell
    set filePath to (POSIX path of (path to temporary items)) & "notchisland-artwork"
    set fileRef to open for access (POSIX file filePath) with write permission
    set eof fileRef to 0
    write artData to fileRef
    close access fileRef
    return filePath
    """

    static func modesScript(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            "tell application \"Spotify\" to return ((shuffling) as string) & linefeed & ((repeating) as string)"
        case .music:
            "tell application \"Music\" to return ((shuffle enabled) as string) & linefeed & ((song repeat is not off) as string)"
        }
    }

    static let spotifyArtworkScript = """
    tell application "Spotify" to return artwork url of current track
    """
}
