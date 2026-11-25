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
