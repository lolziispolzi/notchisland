import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { SymbolLabel("General", systemImage: "gearshape") }
            LayoutSettings(settings: settings)
                .tabItem { SymbolLabel("Layout", systemImage: "rectangle.3.group") }
            WeatherSettings(settings: settings, weather: vm.weather)
                .tabItem { SymbolLabel("Weather", systemImage: "cloud.sun") }
            SportsSettings(settings: settings, sports: vm.sports)
                .tabItem { SymbolLabel("Sports", systemImage: "sportscourt") }
            LyricsSettings(settings: settings, lyrics: vm.lyrics)
                .tabItem { SymbolLabel("Lyrics", systemImage: "quote.bubble") }
            WallpaperSettings(library: vm.wallpapers)
                .tabItem { SymbolLabel("Wallpaper", systemImage: "sparkles.tv") }
            LockScreenSettings(settings: settings, audio: vm.audio, vm: vm, preview: vm.previewLockScreen)
                .tabItem { SymbolLabel("Lock Screen", systemImage: "lock.display") }
            CalendarSettings(settings: settings, calendar: vm.calendar)
                .tabItem { SymbolLabel("Calendar", systemImage: "calendar") }
            DropSettings(settings: settings, shelf: vm.shelf)
                .tabItem { SymbolLabel("Drop Zone", systemImage: "tray.and.arrow.down") }
        }
        .frame(width: 720, height: 600)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Picker("Show on", selection: $settings.displayChoice) {
                    ForEach(DisplayChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle("Glossy island", isOn: $settings.glossyIsland)
                Toggle("Show the island over full-screen apps", isOn: $settings.islandAboveFullScreen)
                    .disabled(SkyLightSpace.aboveFullScreen == nil)
                Text("Uses the same private macOS interface as the lock-screen player. Turning it off takes effect after you quit and reopen NotchIsland.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Behavior")) {
                Toggle("Open on hover", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    LabeledRow("Hover delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                            Text(String(format: "%.2fs", settings.hoverDelay))
                                .compatMonospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                } else {
                    Text("Click the notch to open the island.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
            }

            Section(header: Text("While closed")) {
                Toggle("Live activities", isOn: $settings.showLiveActivities)
                Text("Shows live scores, upcoming events, charging and music next to the notch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Battery in the header", isOn: $settings.showBattery)
            }

            Section(header: Text("About")) {
                LabeledRow("Version", value: SettingsView.version)
            }
        }
        .compatGroupedForm()
    }
}

// MARK: - Layout

private struct LayoutSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section(header: Text("Island size")) {
                Picker("Size", selection: $settings.islandSize) {
                    ForEach(IslandSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .labelsHidden()
            }

            Section(header: Group {
                Text("Widgets")
            }, footer: Group {
                Text("The first visible widget opens by default. You can also press the sliders button in the island to change this without opening Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                ForEach(settings.widgetOrder) { widget in
                    HStack {
                        SymbolImage(widget.symbol)
                            .frame(width: 22)
                        Toggle(widget.title, isOn: Binding(
                            get: { settings.isVisible(widget) },
                            set: { settings.setVisible(widget, $0) }
                        ))
                        Spacer()
                        Button {
                            settings.move(widget, by: -1)
                        } label: {
                            SymbolImage("chevron.up")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(settings.widgetOrder.first == widget)
                        Button {
                            settings.move(widget, by: 1)
                        } label: {
                            SymbolImage("chevron.down")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(settings.widgetOrder.last == widget)
                    }
                }
            }
        }
        .compatGroupedForm()
    }
}

// MARK: - Weather

private struct WeatherSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var weather: WeatherService

    @State private var query = ""
    @State private var results: [WeatherLocation] = []
    @State private var isSearching = false
    @State private var searchMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                Toggle("Use my current location", isOn: $settings.useCurrentLocation)
                if !AppEnvironment.isBundled {
                    Text("Current location works only in the built app (scripts/run-app.sh).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Group {
                Text("City")
            }, footer: Group {
                Text("Used when current location is off or unavailable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                if let location = settings.manualLocation {
                    LabeledRow("City", value: [location.name, location.detail].compactMap { $0 }.joined(separator: ", "))
                }
                HStack {
                    TextField("Search for a city", text: $query, onCommit: search)
                    Button("Search", action: search)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                if isSearching {
                    Spinner().controlSize(.small)
                }
                ForEach(results, id: \.self) { result in
                    Button {
                        settings.manualLocation = result
                        results = []
                        query = ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.name)
                                if let detail = result.detail {
                                    Text(detail).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                if let searchMessage {
                    Text(searchMessage).font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                if let snapshot = weather.snapshot {
                    LabeledRow("Showing", value: snapshot.locationName)
                }
                Button("Refresh Now") { weather.refresh() }
                Text("Weather data from Open-Meteo.com.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .compatGroupedForm()
    }

    private func search() {
        let text = query
        isSearching = true
        searchMessage = nil
        Task {
            do {
                results = try await WeatherService.searchLocations(text)
                searchMessage = results.isEmpty ? "No matching cities." : nil
            } catch {
                searchMessage = "Search failed. Check your connection."
            }
            isSearching = false
        }
    }
}

// MARK: - Sports

private struct SportsSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var sports: SportsService
    @State private var query = ""

    private var results: [SavedTeam] { sports.search(query) }

    var body: some View {
        Form {
            Section(header: Group {
                Text("Your team")
            }) {
                TextField("Search for a team, e.g. Arsenal, Lakers, Yankees", text: $query)
                if sports.teamsState == .loading {
                    HStack {
                        Spinner().controlSize(.small)
                        Text("Loading teams from every league…").font(.caption).foregroundColor(.secondary)
                    }
                } else if let error = sports.teamsState.errorMessage {
                    HStack {
                        Text(error).foregroundColor(.red)
                        Button("Retry") { sports.loadAllTeams() }
                    }
                }
                ForEach(results, id: \.searchKey) { team in
                    Button {
                        settings.favoriteTeam = team
                        if let league = team.league { settings.sportsLeague = league }
                        query = ""
                    } label: {
                        HStack(spacing: 10) {
                            TeamLogo(urlString: team.logoURL, size: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(team.name)
                                if let league = team.league {
                                    Text("\(league.title) · \(league.sportName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if team.searchKey == settings.favoriteTeam?.searchKey {
                                SymbolImage("checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if let team = settings.favoriteTeam {
                Section {
                    HStack(spacing: 10) {
                        TeamLogo(urlString: team.logoURL, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name).font(.headline)
                            Text((team.league ?? settings.sportsLeague).title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Refresh Scores") { sports.refresh() }
                        Button("Remove") { settings.favoriteTeam = nil }
                    }
                }
            }

            Section {
                Text("Shows every game your team plays: league, cups, European and other competitions, and friendlies, each labeled with its competition. While a game is live, the score shows next to the notch and updates every minute. Scores come from ESPN's public data feed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .compatGroupedForm()
        .onAppear { sports.loadAllTeams() }
    }
}

// MARK: - Lyrics

private struct LyricsSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        Form {
            Section(footer: Group {
                Text("Lyrics come from LRCLIB.net, a free community database. Not every song has lyrics, and some have them without timing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                Toggle("Show lyrics for the playing song", isOn: $settings.lyricsEnabled)
                Toggle("Show the current line under the notch", isOn: $settings.lyricsUnderNotch)
                    .disabled(!settings.lyricsEnabled)
            }

            Section(header: Text("Desktop")) {
                Picker("Lyrics on the desktop", selection: $settings.desktopLyricsStyle) {
                    ForEach(DesktopLyricsStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Fill the desktop with the album's colors", isOn: $settings.desktopLyricsTint)
                    .disabled(settings.desktopLyricsStyle == .off)
                Picker("Text size", selection: $settings.desktopLyricsSize) {
                    ForEach(LyricsTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(settings.desktopLyricsStyle == .off)
                Text("Desktop lyrics sit behind your windows, so you see them when the desktop is visible.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(!settings.lyricsEnabled)

            Section(header: Group {
                Text("Sync")
            }, footer: Group {
                Text("If lyrics run late, move the slider right. If they run early, move it left.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                LabeledRow("Timing") {
                    HStack {
                        Slider(value: $settings.lyricsOffset, in: -3...3, step: 0.25)
                        Text(String(format: "%+.2fs", settings.lyricsOffset))
                            .compatMonospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Button("Reset Timing") { settings.lyricsOffset = 0 }
                    .disabled(settings.lyricsOffset == 0)
            }
            .disabled(!settings.lyricsEnabled)
        }
        .compatGroupedForm()
    }
}

// MARK: - Wallpaper

private struct WallpaperSettings: View {
    @ObservedObject var library: WallpaperLibrary
    @State private var prompt = ""
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Theme", selection: $library.theme) {
                        Text("Light").tag(WallpaperTheme.light)
                        Text("Dark").tag(WallpaperTheme.dark)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    if library.isWorking { Spinner().controlSize(.small) }
                    Button("Add Your Own…") { library.importImages() }
                }

                if let message = library.message {
                    Text(message)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .compatTextSelection()
                }
                if let current = library.current, let credit = current.credit {
                    Text("Current: \(credit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .compatTextSelection()
                }

                ForEach(library.sections, id: \.category) { section in
                    Text(section.category.title)
                        .font(.headline)
                    SimpleGrid(items: section.items, columns: 3, spacing: 12) { item in
                        WallpaperTile(item: item, library: library)
                    }
                }

                designSection

                Text("Wall art: public-domain works from the Art Institute of Chicago (CC0). Places: NASA photographs (public domain). Graphic designs: originals made for NotchIsland.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    private var designSection: some View {
        GroupBox(label: SymbolLabel("Design one with Claude", systemImage: "sparkles")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Describe a wallpaper and Claude designs it: the style, colors and mood. NotchIsland then paints it at your screen's full resolution and adds it to your library.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("e.g. calm sunrise over misty hills in peach and lavender", text: $prompt,
                              onCommit: { library.generate(prompt: prompt) })
                    Button("Design") { library.generate(prompt: prompt) }
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || library.isWorking || !library.hasAPIKey)
                }
                Divider()
                if library.hasAPIKey {
                    HStack {
                        SymbolLabel("Anthropic API key saved in your keychain", systemImage: "key.fill")
                            .font(.caption)
                        Spacer()
                        Button("Remove Key") { library.removeAPIKey() }
                    }
                } else {
                    HStack {
                        SecureField("Anthropic API key", text: $apiKey)
                        Button("Save") {
                            library.saveAPIKey(apiKey)
                            apiKey = ""
                        }
                        .disabled(apiKey.isEmpty)
                    }
                    Text("Needs your own key from console.anthropic.com. Each design is one request to Claude, billed to your account. The key stays in your Mac's keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
        }
    }
}

private struct WallpaperTile: View {
    let item: WallpaperItem
    @ObservedObject var library: WallpaperLibrary

    private var isCurrent: Bool { library.currentID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let image = library.thumbnail(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isCurrent ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isCurrent ? 3 : 1)
            )
            HStack(spacing: 4) {
                if item.source == .generated {
                    SymbolImage("sparkles").font(.system(size: 10))
                }
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { library.apply(item) }
        .compatHelp(item.credit ?? "Set as wallpaper")
        .contextMenu {
            Button("Set as Wallpaper") { library.apply(item) }
            if let source = item.sourceURL, let url = URL(string: source) {
                Button("About the Original") { NSWorkspace.shared.open(url) }
            }
            if item.source != .builtIn {
                Divider()
                Button("Remove from Library") { library.remove(item) }
            }
        }
    }
}

// MARK: - Lock screen and glow

private struct LockScreenSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var audio: AudioLevelMonitor
    @ObservedObject var vm: NotchViewModel
    let preview: () -> Void

    var body: some View {
        Form {
            Section(header: Group {
                Text("Lock screen")
            }, footer: Group {
                Text(LockScreenController.isSupported
                     ? "Experimental. macOS has no public way to draw on the lock screen, so this uses a private system interface. It may stop working after a macOS update."
                     : "Not available on this version of macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                Toggle("Show the player on the lock screen", isOn: $settings.lockScreenEnabled)
                    .disabled(!LockScreenController.isSupported)
                Picker("Lyrics style", selection: $settings.lockScreenLyricsStyle) {
                    ForEach(DesktopLyricsStyle.allCases.filter { $0 != .coverAndLyrics && $0 != .off }) { style in
                        Text(style.title).tag(style)
                    }
                }
                .disabled(!settings.lockScreenEnabled || !settings.lyricsEnabled)
                Button("Preview for 10 Seconds", action: preview)
                    .disabled(!settings.lockScreenEnabled)
                Text("While music plays: click the cover to enlarge it, click again for lyrics, and again to go back. A song must be playing for the preview.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Status")) {
                LabeledRow("Lock-screen functions", value: LockScreenController.isSupported ? "Found" : "Not found")
                LabeledRow("Last lock",
                               value: vm.lockScreenStatus.lastLocked.map { DateText.string($0, date: .none, time: .medium) } ?? "Not seen yet")
                Text(vm.lockScreenStatus.lastAttempt)
                    .font(.caption)
                    .compatTextSelection()
                Text("If the lock screen stays empty, lock and unlock once, then send a screenshot of this section.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Group {
                Text("Edge glow")
            }, footer: Group {
                Text("The glow takes the album's color. Without \"Pulse with the sound\" it flashes as each lyric line starts. With it, NotchIsland measures how loud your Mac's sound is; it never records or saves audio.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                Toggle("Glow around the screen edge while music plays", isOn: $settings.edgeGlowEnabled)
                Toggle("Pulse with the sound", isOn: $settings.edgeGlowReactsToAudio)
                    .disabled(!settings.edgeGlowEnabled)
                if settings.edgeGlowReactsToAudio, audio.state == .needsPermission || audio.state == .unavailable {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(audio.state == .needsPermission
                             ? "Needs Screen & System Audio Recording permission. After allowing it, quit and reopen NotchIsland."
                             : "Couldn't start audio metering. Quit and reopen NotchIsland.")
                            .font(.caption)
                            .foregroundColor(.red)
                        HStack {
                            Button("Allow…") { audio.requestPermission() }
                            Button("Open Privacy Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
        }
        .compatGroupedForm()
    }
}

// MARK: - Calendar

private struct CalendarSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var calendar: CalendarService

    private static let headsUpChoices = [0, 5, 10, 15, 30]
    private static let alertChoices = [0, 5, 10, 15, 30, 60]

    private var statusText: String {
        switch calendar.access {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        case .unavailable: "Needs the built app"
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Access")) {
                LabeledRow("Calendar access", value: statusText)
                if calendar.access == .notDetermined {
                    Button("Allow Access") { calendar.requestAccess() }
                } else if calendar.access == .denied {
                    Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                }
            }

            Section(header: Group {
                Text("Reminders")
            }, footer: Group {
                Text("Alerts are saved on the event, so Calendar reminds you on this Mac and your other devices.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                Picker("Show upcoming event in the notch", selection: $settings.eventHeadsUpMinutes) {
                    ForEach(Self.headsUpChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : "\(minutes) min before").tag(minutes)
                    }
                }
                Picker("Alert for new events", selection: $settings.newEventAlertMinutes) {
                    ForEach(Self.alertChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "None" : "\(minutes) min before").tag(minutes)
                    }
                }
            }
        }
        .compatGroupedForm()
    }
}

// MARK: - Drop zone

private struct DropSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        Form {
            Section {
                Toggle("Remove files from the drop zone after copying", isOn: $settings.removeAfterCopy)
            }

            Section(header: Text("Found on this Mac")) {
                ForEach(ShelfStore.detectedDestinations()) { destination in
                    HStack {
                        SymbolLabel(destination.name, systemImage: destination.symbol)
                        Spacer()
                        Text(destination.url.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Section(header: Group {
                Text("Your folders")
            }, footer: Group {
                Text("Copying into a Dropbox, Google Drive, OneDrive or iCloud Drive folder uploads the file through that app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }) {
                ForEach(settings.customDropFolders, id: \.self) { path in
                    HStack {
                        SymbolLabel(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder")
                        Spacer()
                        Button {
                            settings.customDropFolders.removeAll { $0 == path }
                        } label: {
                            SymbolImage("minus.circle")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .compatHelp("Remove")
                    }
                }
                Button("Add Folder…", action: addFolder)
            }
        }
        .compatGroupedForm()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Add Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                if !settings.customDropFolders.contains(url.path) {
                    settings.customDropFolders.append(url.path)
                }
            }
        }
    }
}
