import Metal
import SwiftUI
import XCTest
@testable import NotchIsland

final class WeatherTests: XCTestCase {
    func testWeatherCodeSymbols() {
        XCTAssertEqual(WeatherCode.symbol(for: 0, isDay: true), "sun.max.fill")
        XCTAssertEqual(WeatherCode.symbol(for: 0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(WeatherCode.symbol(for: 2), "cloud.sun.fill")
        XCTAssertEqual(WeatherCode.symbol(for: 63), "cloud.rain.fill")
        XCTAssertEqual(WeatherCode.symbol(for: 65), "cloud.heavyrain.fill")
        XCTAssertEqual(WeatherCode.symbol(for: 73), "cloud.snow.fill")
        XCTAssertEqual(WeatherCode.symbol(for: 95), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherCode.description(for: 3), "Overcast")
        XCTAssertEqual(WeatherCode.description(for: 1234), "Unknown")
    }

    func testForecastParsing() throws {
        let json = """
        {
          "latitude": 40.71, "longitude": -74.01, "timezone": "America/New_York",
          "current": {
            "time": "2026-11-24T10:00", "temperature_2m": 8.4, "apparent_temperature": 5.9,
            "weather_code": 3, "is_day": 1, "wind_speed_10m": 14.2, "relative_humidity_2m": 71
          },
          "daily": {
            "time": ["2026-11-24", "2026-11-25"],
            "weather_code": [3, 61],
            "temperature_2m_max": [10.1, 7.6],
            "temperature_2m_min": [4.2, 3.0],
            "precipitation_probability_max": [10, null]
          }
        }
        """
        let snapshot = try OpenMeteo.snapshot(from: Data(json.utf8), locationName: "New York", unit: .celsius)
        XCTAssertEqual(snapshot.locationName, "New York")
        XCTAssertEqual(snapshot.temperature, 8.4)
        XCTAssertEqual(snapshot.feelsLike, 5.9)
        XCTAssertEqual(snapshot.code, 3)
        XCTAssertTrue(snapshot.isDay)
        XCTAssertEqual(snapshot.humidity, 71)
        XCTAssertEqual(snapshot.days.count, 2)
        XCTAssertEqual(snapshot.days[0].high, 10.1)
        XCTAssertEqual(snapshot.days[0].precipitationChance, 10)
        XCTAssertNil(snapshot.days[1].precipitationChance)
        XCTAssertEqual(snapshot.days[1].code, 61)
    }

    func testGeocodingParsing() throws {
        let json = """
        {"results": [
          {"name": "London", "latitude": 51.5, "longitude": -0.12, "country": "United Kingdom", "admin1": "England"},
          {"name": "London", "latitude": 42.98, "longitude": -81.23, "country": "Canada"}
        ]}
        """
        let locations = try OpenMeteo.locations(from: Data(json.utf8))
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].detail, "England, United Kingdom")
        XCTAssertEqual(locations[1].detail, "Canada")
        XCTAssertEqual(try OpenMeteo.locations(from: Data("{}".utf8)), [])
    }

    func testForecastURLUsesUnits() {
        let url = OpenMeteo.forecastURL(latitude: 1, longitude: 2, unit: .fahrenheit).absoluteString
        XCTAssertTrue(url.contains("temperature_unit=fahrenheit"))
        XCTAssertTrue(url.contains("wind_speed_unit=mph"))
    }

    func testTemperatureFormat() {
        XCTAssertEqual(Temperature.string(21.6), "22°")
        XCTAssertEqual(Temperature.string(-0.4), "0°")
    }
}

final class SportsTests: XCTestCase {
    private let scheduleJSON = """
    {"events": [
      {"id": "1", "date": "2026-11-20T00:30Z",
       "competitions": [{"date": "2026-11-20T00:30Z",
         "competitors": [
           {"homeAway": "home", "team": {"id": "13", "displayName": "Los Angeles Lakers", "abbreviation": "LAL", "logos": [{"href": "https://a/lal.png"}]}, "score": {"value": 112.0, "displayValue": "112"}},
           {"homeAway": "away", "team": {"id": "2", "displayName": "Boston Celtics", "abbreviation": "BOS"}, "score": {"value": 104.0, "displayValue": "104"}}
         ],
         "status": {"type": {"state": "post", "completed": true, "shortDetail": "Final"}}}]},
      {"id": "2", "date": "2026-11-25T03:00Z",
       "competitions": [{
         "competitors": [
           {"homeAway": "away", "team": {"id": "13", "displayName": "Los Angeles Lakers", "abbreviation": "LAL"}},
           {"homeAway": "home", "team": {"id": 9, "displayName": "Golden State Warriors", "abbreviation": "GS", "logo": "https://a/gs.png"}, "score": "0"}
         ],
         "status": {"type": {"state": "pre", "shortDetail": "11/24 - 7:00 PM PST"}}}]}
    ]}
    """

    func testScheduleParsing() throws {
        let games = try ESPN.games(from: Data(scheduleJSON.utf8))
        XCTAssertEqual(games.count, 2)

        let final = games[0]
        XCTAssertEqual(final.state, .post)
        XCTAssertEqual(final.home.team.abbreviation, "LAL")
        XCTAssertEqual(final.home.team.logoURL, "https://a/lal.png")
        XCTAssertEqual(final.home.score, "112")
        XCTAssertEqual(final.away.score, "104")
        XCTAssertEqual(final.detail, "Final")
        XCTAssertEqual(final.result(for: "13"), "W")
        XCTAssertEqual(final.result(for: "2"), "L")

        let next = games[1]
        XCTAssertEqual(next.state, .pre)
        XCTAssertEqual(next.home.team.id, "9")
        XCTAssertEqual(next.home.team.logoURL, "https://a/gs.png")
        XCTAssertFalse(next.side(of: "13")?.isHome ?? true)
        XCTAssertEqual(next.opponent(of: "13")?.team.abbreviation, "GS")
        XCTAssertNil(next.result(for: "13"))
    }

    func testDateParsing() {
        XCTAssertNotNil(ESPN.parseDate("2026-11-20T00:30Z"))
        XCTAssertNotNil(ESPN.parseDate("2026-11-20T00:30:00Z"))
        XCTAssertNotNil(ESPN.parseDate("2026-11-20T00:30:00.000Z"))
        XCTAssertNil(ESPN.parseDate("not a date"))
        XCTAssertEqual(ESPN.parseDate("2026-11-20T00:30Z"), ESPN.parseDate("2026-11-20T00:30:00Z"))
    }

    func testTeamsParsing() throws {
        let json = """
        {"sports": [{"leagues": [{"teams": [
          {"team": {"id": "2", "displayName": "Boston Celtics", "abbreviation": "BOS"}},
          {"team": {"id": "1", "displayName": "Atlanta Hawks", "abbreviation": "ATL", "logos": [{"href": "https://a/atl.png"}]}}
        ]}]}]}
        """
        let teams = try ESPN.teams(from: Data(json.utf8))
        XCTAssertEqual(teams.map(\.name), ["Atlanta Hawks", "Boston Celtics"])
        XCTAssertEqual(teams[0].logoURL, "https://a/atl.png")
    }

    private func game(_ id: String, _ state: Game.State, _ date: Date) -> Game {
        let team = SavedTeam(id: "1", name: "A", abbreviation: "A", logoURL: nil)
        let other = SavedTeam(id: "2", name: "B", abbreviation: "B", logoURL: nil)
        return Game(id: id, date: date, state: state, detail: "",
                    home: TeamSide(team: team, score: nil, isHome: true),
                    away: TeamSide(team: other, score: nil, isHome: false))
    }

    func testFeaturedGamePrefersLive() {
        let now = Date()
        let games = [game("old", .post, now.addingTimeInterval(-86400)),
                     game("live", .live, now.addingTimeInterval(-3600)),
                     game("next", .pre, now.addingTimeInterval(86400))]
        XCTAssertEqual(SportsSnapshot.make(from: games, now: now).featured?.id, "live")
    }

    func testFeaturedGameShowsRecentResultThenNextGame() {
        let now = Date()
        let recent = game("recent", .post, now.addingTimeInterval(-3 * 3600))
        let next = game("next", .pre, now.addingTimeInterval(86400))
        XCTAssertEqual(SportsSnapshot.make(from: [recent, next], now: now).featured?.id, "recent")

        let old = game("old", .post, now.addingTimeInterval(-3 * 86400))
        let snapshot = SportsSnapshot.make(from: [old, next], now: now)
        XCTAssertEqual(snapshot.featured?.id, "next")
        XCTAssertEqual(snapshot.recent.map(\.id), ["old"])
        XCTAssertTrue(snapshot.upcoming.isEmpty)
    }

    func testDeduplicatedKeepsOnePerID() {
        let now = Date()
        let games = ESPN.deduplicated([game("a", .pre, now), game("a", .live, now), game("b", .pre, now.addingTimeInterval(10))])
        XCTAssertEqual(games.map(\.id), ["a", "b"])
        XCTAssertEqual(games[0].state, .live)
    }
}

final class CalendarTests: XCTestCase {
    private func event(_ title: String, in minutes: Double, allDay: Bool = false, now: Date) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEvent(id: title, title: title, start: start, end: start.addingTimeInterval(3600),
                             isAllDay: allDay, color: .blue, location: nil)
    }

    func testHeadsUpPicksNextTimedEventInsideWindow() {
        let now = Date()
        let events = [event("All day", in: 1, allDay: true, now: now),
                      event("Standup", in: 8, now: now),
                      event("Lunch", in: 120, now: now)]
        XCTAssertEqual(CalendarService.headsUpEvent(in: events, now: now, lead: 600)?.title, "Standup")
        XCTAssertNil(CalendarService.headsUpEvent(in: events, now: now, lead: 300))
    }

    func testCountdown() {
        let now = Date()
        XCTAssertEqual(RelativeTime.countdown(to: now.addingTimeInterval(-5), from: now), "now")
        XCTAssertEqual(RelativeTime.countdown(to: now.addingTimeInterval(7.2 * 60), from: now), "in 8m")
        XCTAssertEqual(RelativeTime.countdown(to: now.addingTimeInterval(125 * 60), from: now), "in 2h")
    }

    func testEventLabelDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9))!
        let later = calendar.date(byAdding: .hour, value: 3, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertTrue(RelativeTime.eventLabel(start: later, isAllDay: false, now: now, calendar: calendar).hasPrefix("Today · "))
        XCTAssertEqual(RelativeTime.eventLabel(start: tomorrow, isAllDay: true, now: now, calendar: calendar), "Tomorrow · All day")
    }
}

final class LayoutTests: XCTestCase {
    func testMoveWidget() {
        let order: [WidgetKind] = [.media, .weather, .calendar, .sports, .drop]
        XCTAssertEqual(AppSettings.moved(order, .calendar, by: -1), [.media, .calendar, .weather, .sports, .drop])
        XCTAssertEqual(AppSettings.moved(order, .media, by: -1), order)
        XCTAssertEqual(AppSettings.moved(order, .drop, by: 5), order)
    }

    func testNormalizedOrderAddsMissingAndDropsUnknown() {
        XCTAssertEqual(AppSettings.normalizedOrder(["sports", "bogus", "sports", "media"]),
                       [.sports, .media, .weather, .calendar, .drop, .notes])
        XCTAssertEqual(AppSettings.normalizedOrder([]), WidgetKind.allCases)
    }

    func testIslandSizesFitInsidePanel() {
        for size in IslandSize.allCases {
            XCTAssertLessThanOrEqual(size.openSize.width, NotchGeometry.maxOpenSize.width)
            XCTAssertLessThanOrEqual(size.openSize.height + NotchGeometry.editBarHeight, NotchGeometry.maxOpenSize.height)
        }
    }
}

final class DropZoneTests: XCTestCase {
    func testUniqueDestinationAddsNumber() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertEqual(ShelfStore.uniqueDestination(for: source, in: folder).lastPathComponent, "report.pdf")

        FileManager.default.createFile(atPath: folder.appendingPathComponent("report.pdf").path, contents: Data())
        XCTAssertEqual(ShelfStore.uniqueDestination(for: source, in: folder).lastPathComponent, "report 2.pdf")

        FileManager.default.createFile(atPath: folder.appendingPathComponent("report 2.pdf").path, contents: Data())
        XCTAssertEqual(ShelfStore.uniqueDestination(for: source, in: folder).lastPathComponent, "report 3.pdf")
    }

    func testTransferCopiesFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("note.txt")
        try Data("hi".utf8).write(to: file)
        let missing = root.appendingPathComponent("missing.txt")

        let result = ShelfStore.transfer([file, missing], to: target, move: false)
        XCTAssertEqual(result.succeeded, [file])
        XCTAssertEqual(result.failed, [missing])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("note.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCountLabel() {
        XCTAssertEqual(ShelfStore.countLabel(1), "1 item")
        XCTAssertEqual(ShelfStore.countLabel(3), "3 items")
    }
}

final class PlaybackModesTests: XCTestCase {
    func testModesParsing() {
        XCTAssertEqual(PlaybackUpdate.modes(from: "true\nfalse")?.shuffle, true)
        XCTAssertEqual(PlaybackUpdate.modes(from: "true\nfalse")?.repeating, false)
        XCTAssertEqual(PlaybackUpdate.modes(from: "False\nTRUE")?.repeating, true)
        XCTAssertNil(PlaybackUpdate.modes(from: "true"))
        XCTAssertNil(PlaybackUpdate.modes(from: "yes\nno"))
    }
}

@MainActor
final class NotesTests: XCTestCase {
    private func makeFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testAddEditPinDeleteAndReload() {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = NotesStore(directory: folder)
        XCTAssertTrue(store.notes.isEmpty)

        let first = store.add()
        store.updateText(first.id, "Buy milk\nand eggs")
        let second = store.add()
        store.updateText(second.id, "Call mom")
        XCTAssertEqual(store.selectedID, second.id)
        XCTAssertEqual(store.notes.map(\.title), ["Call mom", "Buy milk"])

        // Pinned notes go to the top even if older.
        store.togglePin(first.id)
        XCTAssertEqual(store.notes.first?.id, first.id)

        store.setColor(second.id, .green)
        store.saveNow()

        let reloaded = NotesStore(directory: folder)
        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertEqual(reloaded.notes.first?.text, "Buy milk\nand eggs")
        XCTAssertTrue(reloaded.notes.first?.isPinned ?? false)
        XCTAssertEqual(reloaded.note(second.id)?.color, .green)

        reloaded.delete(first.id)
        XCTAssertEqual(reloaded.notes.map(\.id), [second.id])
        XCTAssertEqual(reloaded.selectedID, second.id)
    }

    func testTitle() {
        var note = Note(id: UUID(), text: "", color: .yellow, isPinned: false, updatedAt: Date())
        XCTAssertEqual(note.title, "New Note")
        note.text = "\n   \n  Meeting notes  \nsecond line"
        XCTAssertEqual(note.title, "Meeting notes")
        note.text = String(repeating: "a", count: 50)
        XCTAssertEqual(note.title, String(repeating: "a", count: 40) + "…")
    }
}

final class HeaderHitTestTests: XCTestCase {
    func testHeaderActionHitTest() {
        let targets: [String: CGRect] = [
            "tab.weather": CGRect(x: 40, y: 5, width: 24, height: 22),
            "settings": CGRect(x: 500, y: 5, width: 24, height: 22),
        ]
        XCTAssertEqual(NotchViewModel.headerAction(at: CGPoint(x: 50, y: 15), in: targets), "tab.weather")
        // A little slack around each button.
        XCTAssertEqual(NotchViewModel.headerAction(at: CGPoint(x: 39, y: 3), in: targets), "tab.weather")
        XCTAssertEqual(NotchViewModel.headerAction(at: CGPoint(x: 510, y: 20), in: targets), "settings")
        XCTAssertNil(NotchViewModel.headerAction(at: CGPoint(x: 200, y: 15), in: targets))
        XCTAssertNil(NotchViewModel.headerAction(at: CGPoint(x: 50, y: 60), in: targets))
    }
}

final class LyricsTests: XCTestCase {
    func testParseLRC() {
        let text = """
        [ar:Some Artist]
        [ti:Some Song]
        [00:12.50]First line
        [00:15.00][01:02.25]Chorus line
        [00:20.10]
        [00:18.3]Second line
        not a lyric line
        """
        let lines = LRC.parse(text)
        XCTAssertEqual(lines.map(\.text), ["First line", "Chorus line", "Second line", "", "Chorus line"])
        XCTAssertEqual(lines.map(\.time), [12.5, 15, 18.3, 20.1, 62.25])
        XCTAssertEqual(lines.map(\.id), [0, 1, 2, 3, 4])
    }

    func testParseOffset() {
        let lines = LRC.parse("[offset:+500]\n[00:10.00]Line")
        XCTAssertEqual(lines.first?.time, 9.5)
    }

    func testCurrentIndex() {
        let lines = LRC.parse("[00:05.00]a\n[00:10.00]b\n[00:15.00]c")
        XCTAssertNil(LRC.index(at: 2, in: lines))
        XCTAssertEqual(LRC.index(at: 5, in: lines), 0)
        XCTAssertEqual(LRC.index(at: 9.99, in: lines), 0)
        XCTAssertEqual(LRC.index(at: 10, in: lines), 1)
        XCTAssertEqual(LRC.index(at: 300, in: lines), 2)
        XCTAssertNil(LRC.index(at: 10, in: []))
    }

    func testCleanTitleAndArtist() {
        XCTAssertEqual(LRCLIB.cleanTitle("Let It Be - Remastered 2009"), "Let It Be")
        XCTAssertEqual(LRCLIB.cleanTitle("Sweet (feat. Someone)"), "Sweet")
        XCTAssertEqual(LRCLIB.cleanTitle("Song [Live]"), "Song")
        XCTAssertEqual(LRCLIB.cleanTitle("(What's the Story) Morning Glory?"), "(What's the Story) Morning Glory?")
        XCTAssertEqual(LRCLIB.primaryArtist("Artist A, Artist B"), "Artist A")
        XCTAssertEqual(LRCLIB.primaryArtist("Simon & Garfunkel"), "Simon")
        XCTAssertEqual(LRCLIB.primaryArtist("Solo"), "Solo")
    }

    func testRecordDecodingAndBestPick() throws {
        let json = """
        [
          {"id": 1, "trackName": "Song", "artistName": "A", "duration": 300, "instrumental": false,
           "plainLyrics": "x", "syncedLyrics": "[00:01.00]wrong length"},
          {"id": 2, "trackName": "Song", "artistName": "A", "duration": 201, "instrumental": false,
           "plainLyrics": "hello", "syncedLyrics": "[00:01.00]hello"},
          {"id": 3, "trackName": "Song", "artistName": "A", "duration": 200, "instrumental": false,
           "plainLyrics": "plain only", "syncedLyrics": null}
        ]
        """
        let records = try JSONDecoder().decode([LRCLIB.Record].self, from: Data(json.utf8))
        XCTAssertEqual(LRCLIB.best(records, duration: 200)?.id, 2)

        let lyrics = try XCTUnwrap(LRCLIB.lyrics(from: records[2]))
        XCTAssertFalse(lyrics.isSynced)
        XCTAssertEqual(lyrics.plain, ["plain only"])

        let empty = LRCLIB.Record(id: 4, trackName: nil, artistName: nil, albumName: nil, duration: nil,
                                  instrumental: false, plainLyrics: nil, syncedLyrics: nil)
        XCTAssertNil(LRCLIB.lyrics(from: empty))
        let instrumental = LRCLIB.Record(id: 5, trackName: nil, artistName: nil, albumName: nil, duration: nil,
                                         instrumental: true, plainLyrics: nil, syncedLyrics: nil)
        XCTAssertEqual(LRCLIB.lyrics(from: instrumental)?.instrumental, true)
    }

    func testGetURL() {
        let track = Track(title: "Spinning", artist: "Pentire", album: "", duration: 219.4)
        let url = LRCLIB.getURL(for: track).absoluteString
        XCTAssertTrue(url.hasPrefix("https://lrclib.net/api/get?"))
        XCTAssertTrue(url.contains("track_name=Spinning"))
        XCTAssertTrue(url.contains("duration=219"))
        XCTAssertFalse(url.contains("album_name"))
    }
}

final class PaletteTests: XCTestCase {
    func testPaletteFindsStrongColors() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        // Plain device RGB colors: dynamic system colors can't be written into a bitmap.
        let red = NSColor(deviceRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        let blue = NSColor(deviceRed: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        rep.setColor(red, atX: 0, y: 0)
        rep.setColor(red, atX: 0, y: 1)
        rep.setColor(blue, atX: 1, y: 0)
        rep.setColor(blue, atX: 1, y: 1)
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.addRepresentation(rep)

        let colors = ArtworkPalette.colors(from: image)
        XCTAssertEqual(colors.count, 2)
        let first = try XCTUnwrap(colors.first?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(first.saturationComponent, 0.4)
    }

    func testHueDistanceWraps() {
        XCTAssertEqual(ArtworkPalette.hueDistance(0.05, 0.95), 0.1, accuracy: 0.0001)
    }
}

final class StarsAndGlowTests: XCTestCase {
    func testConstellationLayoutIsDeterministicAndInBounds() {
        let size = CGSize(width: 600, height: 240)
        let a = ConstellationLayout.points(count: 6, seed: 42, size: size)
        let b = ConstellationLayout.points(count: 6, seed: 42, size: size)
        let c = ConstellationLayout.points(count: 6, seed: 43, size: size)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.count, 6)
        for point in a {
            XCTAssertTrue((0...size.width).contains(point.x))
            XCTAssertTrue((0...size.height).contains(point.y))
        }
        // Stars run left to right.
        XCTAssertLessThan(a.first!.x, a.last!.x)
        XCTAssertTrue(ConstellationLayout.points(count: 0, seed: 1, size: size).isEmpty)
    }

    func testConstellationFrameRevealsWordsOverTheLine() {
        let lines = LRC.parse("[00:10.00]Turn down the lights\n[00:14.00]Next")
        XCTAssertNil(ConstellationFrame.make(lines: lines, elapsed: 5))

        let start = ConstellationFrame.make(lines: lines, elapsed: 10.01)
        XCTAssertEqual(start?.visibleCount, 1)
        XCTAssertEqual(start?.currentWord, "Turn")

        let middle = ConstellationFrame.make(lines: lines, elapsed: 11.8)
        XCTAssertEqual(middle?.visibleCount, 3)
        XCTAssertEqual(middle?.currentWord, "the")

        let end = ConstellationFrame.make(lines: lines, elapsed: 13.9)
        XCTAssertEqual(end?.visibleCount, 4)
        XCTAssertEqual(end?.words, ["Turn", "down", "the", "lights"])

        let breakLine = ConstellationFrame.make(lines: LRC.parse("[00:01.00]"), elapsed: 2)
        XCTAssertEqual(breakLine?.currentWord, "♪")
    }

    func testGlowPulse() {
        let calm = GlowPulse.intensity(sinceLineStart: nil, time: 0)
        let flash = GlowPulse.intensity(sinceLineStart: 0, time: 0)
        let faded = GlowPulse.intensity(sinceLineStart: 2, time: 0)
        XCTAssertGreaterThan(flash, calm)
        XCTAssertEqual(faded, calm, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(flash, 1)
    }

    func testScreenOutlineDipsAroundNotch() {
        let rect = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = CGRect(x: 663, y: 0, width: 186, height: 32)
        let path = ScreenOutline(notch: notch).path(in: rect)
        XCTAssertEqual(path.boundingRect, rect)
        XCTAssertTrue(path.contains(CGPoint(x: 100, y: 100)))
        // Inside the notch dip is outside the outline.
        XCTAssertFalse(path.contains(CGPoint(x: 756, y: 10)))
    }

    func testAudioLevelNormalization() {
        XCTAssertEqual(AudioLevelOutput.normalized(rms: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelOutput.normalized(rms: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioLevelOutput.normalized(rms: 0.0316), 0.4, accuracy: 0.01)
    }
}

@MainActor
final class LockScreenTests: XCTestCase {
    func testModeCycle() {
        XCTAssertEqual(LockScreenMode.compact.next(hasLyrics: true), .cover)
        XCTAssertEqual(LockScreenMode.cover.next(hasLyrics: true), .lyrics)
        XCTAssertEqual(LockScreenMode.cover.next(hasLyrics: false), .compact)
        XCTAssertEqual(LockScreenMode.lyrics.next(hasLyrics: true), .compact)
    }

    func testPlayerFramesStayOnScreenAndCentered() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        for mode in [LockScreenMode.compact, .cover, .lyrics] {
            let frame = LockScreenController.playerFrame(mode: mode, in: screen)
            XCTAssertTrue(screen.contains(frame), "\(mode)")
            XCTAssertEqual(frame.midX, screen.midX)
            // Leave the top fifth for the macOS clock.
            XCTAssertLessThan(frame.maxY, screen.maxY - screen.height * 0.2, "\(mode)")
        }
        let cover = LockScreenController.playerFrame(mode: .cover, in: screen)
        let compact = LockScreenController.playerFrame(mode: .compact, in: screen)
        XCTAssertGreaterThan(cover.height, compact.height)
    }
}

final class LiveWallpaperTests: XCTestCase {
    func testUniformLayoutMatchesShader() {
        // float2, 3 floats, int, float2 padding, two float4s: 64 bytes, colors at 32 and 48.
        XCTAssertEqual(MemoryLayout<WallpaperUniforms>.stride, 64)
        XCTAssertEqual(MemoryLayout<WallpaperUniforms>.offset(of: \.colorA), 32)
        XCTAssertEqual(MemoryLayout<WallpaperUniforms>.offset(of: \.colorB), 48)
    }

    func testShaderCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device on this machine")
        }
        let library = try device.makeLibrary(source: WallpaperShader.source, options: nil)
        XCTAssertNotNil(library.makeFunction(name: "wallpaper_vertex"))
        XCTAssertNotNil(library.makeFunction(name: "wallpaper_fragment"))
    }

    func testSceneIndices() {
        XCTAssertEqual(WallpaperScene.auroraLake.shaderIndex, 0)
        XCTAssertEqual(WallpaperScene.contours.shaderIndex, 1)
        XCTAssertEqual(WallpaperScene.nebula.shaderIndex, 2)
    }

    func testBeatDetection() {
        XCTAssertTrue(AudioLevelMonitor.isBeat(value: 0.7, average: 0.4, sinceLastBeat: 1))
        XCTAssertFalse(AudioLevelMonitor.isBeat(value: 0.45, average: 0.4, sinceLastBeat: 1))
        XCTAssertFalse(AudioLevelMonitor.isBeat(value: 0.7, average: 0.4, sinceLastBeat: 0.1))
    }

    @MainActor
    func testAlbumColorsAreBright() throws {
        let dark = NSColor(srgbRed: 0.2, green: 0.05, blue: 0.05, alpha: 1)
        let (first, second) = try XCTUnwrap(LiveWallpaperController.albumColors([dark]))
        XCTAssertGreaterThan(first.x, 0.8)
        XCTAssertEqual(first, second)
        XCTAssertNil(LiveWallpaperController.albumColors([]))
    }
}
