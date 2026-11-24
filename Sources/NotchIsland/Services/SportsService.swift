import Combine
import Foundation

enum SportsLeague: String, CaseIterable, Identifiable, Codable {
    case nfl, nba, wnba, mlb, nhl
    case mls, premierLeague, laLiga, bundesliga, serieA, ligue1, championsLeague
    case collegeFootball, collegeBasketball

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nfl: "NFL"
        case .nba: "NBA"
        case .wnba: "WNBA"
        case .mlb: "MLB"
        case .nhl: "NHL"
        case .mls: "MLS"
        case .premierLeague: "Premier League"
        case .laLiga: "La Liga"
        case .bundesliga: "Bundesliga"
        case .serieA: "Serie A"
        case .ligue1: "Ligue 1"
        case .championsLeague: "Champions League"
        case .collegeFootball: "College Football"
        case .collegeBasketball: "College Basketball"
        }
    }

    var sportName: String {
        switch self {
        case .nfl, .collegeFootball: "Football"
        case .nba, .wnba, .collegeBasketball: "Basketball"
        case .mlb: "Baseball"
        case .nhl: "Hockey"
        default: "Soccer"
        }
    }

    /// ESPN path: "{sport}/{league}".
    var path: String {
        switch self {
        case .nfl: "football/nfl"
        case .nba: "basketball/nba"
        case .wnba: "basketball/wnba"
        case .mlb: "baseball/mlb"
        case .nhl: "hockey/nhl"
        case .mls: "soccer/usa.1"
        case .premierLeague: "soccer/eng.1"
        case .laLiga: "soccer/esp.1"
        case .bundesliga: "soccer/ger.1"
        case .serieA: "soccer/ita.1"
        case .ligue1: "soccer/fra.1"
        case .championsLeague: "soccer/uefa.champions"
        case .collegeFootball: "football/college-football"
        case .collegeBasketball: "basketball/mens-college-basketball"
        }
    }

    var symbol: String {
        switch sportName {
        case "Football": "football.fill"
        case "Basketball": "basketball.fill"
        case "Baseball": "baseball.fill"
        case "Hockey": "hockey.puck.fill"
        default: "soccerball"
        }
    }

    var isSoccer: Bool { path.hasPrefix("soccer/") }
}

struct SavedTeam: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var abbreviation: String
    var logoURL: String?

    var shortLabel: String { abbreviation.isEmpty ? name : abbreviation }
}

struct TeamSide: Equatable {
    var team: SavedTeam
    var score: String?
    var isHome: Bool
}

struct Game: Equatable, Identifiable {
    enum State: String {
        case pre
        case live = "in"
        case post
    }

    var id: String
    var date: Date
    var state: State
    /// ESPN's short status, e.g. "Final", "Q3 5:12", "7:30 PM ET".
    var detail: String
    var home: TeamSide
    var away: TeamSide

    func side(of teamID: String) -> TeamSide? {
        if home.team.id == teamID { return home }
        if away.team.id == teamID { return away }
        return nil
    }

    func opponent(of teamID: String) -> TeamSide? {
        if home.team.id == teamID { return away }
        if away.team.id == teamID { return home }
        return nil
    }

    /// "W", "L" or "D" for a finished game, from the given team's point of view.
    func result(for teamID: String) -> String? {
        guard state == .post,
              let mine = side(of: teamID).flatMap({ Double($0.score ?? "") }),
              let theirs = opponent(of: teamID).flatMap({ Double($0.score ?? "") })
        else { return nil }
        if mine > theirs { return "W" }
        if mine < theirs { return "L" }
        return "D"
    }
}

struct SportsSnapshot: Equatable {
    /// The game to show big: live, else a result from the last 12 hours, else the next game.
    var featured: Game?
    var upcoming: [Game]
    var recent: [Game]

    static func make(from games: [Game], now: Date) -> SportsSnapshot {
        let sorted = games.sorted { $0.date < $1.date }
        let featured = pickFeatured(sorted, now: now)
        let upcoming = sorted.filter { $0.state == .pre && $0.date > now && $0.id != featured?.id }
        let recent = sorted.filter { $0.state == .post && $0.id != featured?.id }.reversed()
        return SportsSnapshot(featured: featured,
                              upcoming: Array(upcoming.prefix(3)),
                              recent: Array(recent.prefix(3)))
    }

    static func pickFeatured(_ sorted: [Game], now: Date) -> Game? {
        if let live = sorted.first(where: { $0.state == .live }) { return live }
        if let recent = sorted.last(where: { $0.state == .post && now.timeIntervalSince($0.date) < 12 * 3600 }) {
            return recent
        }
        if let next = sorted.first(where: { $0.state == .pre && $0.date > now.addingTimeInterval(-3 * 3600) }) {
            return next
        }
        return sorted.last(where: { $0.state == .post })
    }
}

/// ESPN's public site API. Unofficial and undocumented, but needs no key.
enum ESPN {
    static let base = "https://site.api.espn.com/apis/site/v2/sports/"

    static func teamsURL(_ league: SportsLeague) -> URL {
        URL(string: base + league.path + "/teams?limit=1000")!
    }

    static func scheduleURL(_ league: SportsLeague, teamID: String, fixtures: Bool = false) -> URL {
        var string = base + league.path + "/teams/\(teamID)/schedule"
        if fixtures { string += "?fixture=true" }
        return URL(string: string)!
    }

    // MARK: Response types (only the fields used)

    struct TeamsResponse: Decodable {
        struct Sport: Decodable { let leagues: [League]? }
        struct League: Decodable { let teams: [Wrapper]? }
        struct Wrapper: Decodable { let team: Team }
        let sports: [Sport]?
    }

    struct Team: Decodable {
        struct Logo: Decodable { let href: String }

        let id: String
        let displayName: String?
        let shortDisplayName: String?
        let abbreviation: String?
        let logo: String?
        let logos: [Logo]?

        enum CodingKeys: String, CodingKey {
            case id, displayName, shortDisplayName, abbreviation, logo, logos
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? container.decode(String.self, forKey: .id) {
                id = string
            } else {
                id = try String(container.decode(Int.self, forKey: .id))
            }
            displayName = try? container.decode(String.self, forKey: .displayName)
            shortDisplayName = try? container.decode(String.self, forKey: .shortDisplayName)
            abbreviation = try? container.decode(String.self, forKey: .abbreviation)
            logo = try? container.decode(String.self, forKey: .logo)
            logos = try? container.decode([Logo].self, forKey: .logos)
        }

        var saved: SavedTeam {
            SavedTeam(id: id,
                      name: displayName ?? shortDisplayName ?? abbreviation ?? id,
                      abbreviation: abbreviation ?? "",
                      logoURL: logo ?? logos?.first?.href)
        }
    }

    struct ScheduleResponse: Decodable {
        let events: [Event]?
    }

    struct Event: Decodable {
        let id: String
        let date: String?
        let competitions: [Competition]?
    }

    struct Competition: Decodable {
        let date: String?
        let competitors: [Competitor]?
        let status: Status?
    }

    struct Competitor: Decodable {
        let homeAway: String?
        let team: Team?
        let score: Score?
    }

    struct Status: Decodable {
        struct StatusType: Decodable {
            let state: String?
            let shortDetail: String?
            let detail: String?
        }
        let type: StatusType?
    }

    /// Scores come as "102" on scoreboards and as {"value": 102, "displayValue": "102"} on schedules.
    struct Score: Decodable {
        let display: String

        private enum Keys: String, CodingKey { case value, displayValue }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if let string = try? single.decode(String.self) {
                    display = string
                    return
                }
                if let number = try? single.decode(Double.self) {
                    display = Score.format(number)
                    return
                }
            }
            let object = try decoder.container(keyedBy: Keys.self)
            if let string = try? object.decode(String.self, forKey: .displayValue) {
                display = string
            } else if let number = try? object.decode(Double.self, forKey: .value) {
                display = Score.format(number)
            } else {
                display = ""
            }
        }

        static func format(_ number: Double) -> String {
            number.rounded() == number ? String(Int(number)) : String(number)
        }
    }

    // MARK: Parsing

    static func teams(from data: Data) throws -> [SavedTeam] {
        let response = try JSONDecoder().decode(TeamsResponse.self, from: data)
        let teams = response.sports?.first?.leagues?.first?.teams?.map(\.team.saved) ?? []
        return teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func games(from data: Data) throws -> [Game] {
        let response = try JSONDecoder().decode(ScheduleResponse.self, from: data)
        return (response.events ?? []).compactMap(game(from:))
    }

    static func game(from event: Event) -> Game? {
        guard let competition = event.competitions?.first,
              let competitors = competition.competitors, competitors.count >= 2
        else { return nil }

        let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
        guard let homeTeam = home.team?.saved,
              let awayTeam = away.team?.saved,
              let date = parseDate(competition.date ?? event.date ?? "")
        else { return nil }

        let status = competition.status?.type
        return Game(id: event.id,
                    date: date,
                    state: Game.State(rawValue: status?.state ?? "pre") ?? .pre,
                    detail: status?.shortDetail ?? status?.detail ?? "",
                    home: TeamSide(team: homeTeam, score: home.score?.display, isHome: true),
                    away: TeamSide(team: awayTeam, score: away.score?.display, isHome: false))
    }

    static func deduplicated(_ games: [Game]) -> [Game] {
        var byID: [String: Game] = [:]
        for game in games { byID[game.id] = game }
        return byID.values.sorted { $0.date < $1.date }
    }

    /// ESPN dates look like "2025-10-22T02:00Z" (no seconds) or full ISO 8601.
    static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return formatter.date(from: string)
    }
}

/// Follows the favorite team. Refreshes when the island opens, every minute while a game
/// is live, and once when the next game starts. Otherwise it does nothing.
@MainActor
final class SportsService: ObservableObject {
    @Published private(set) var snapshot: SportsSnapshot?
    @Published private(set) var state: LoadState = .idle
    /// Teams of the selected league, for the Settings picker.
    @Published private(set) var teams: [SavedTeam] = []
    @Published private(set) var teamsState: LoadState = .idle

    private let settings: AppSettings
    private var lastFetch: Date?
    private var liveTimer: Timer?
    private var kickoffWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings

        settings.$favoriteTeam
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.snapshot = nil
                self?.lastFetch = nil
                self?.refresh()
            }
            .store(in: &cancellables)

        // Load at launch so a live game can show next to the notch right away.
        if settings.favoriteTeam != nil, settings.isVisible(.sports) {
            refresh()
        }
    }

    func refreshIfStale() {
        let maxAge: TimeInterval = snapshot?.featured?.state == .live ? 60 : 300
        if let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard state != .loading else { return }
        guard let team = settings.favoriteTeam else {
            snapshot = nil
            stopTimers()
            return
        }
        let league = settings.sportsLeague
        state = .loading
        Task {
            do {
                let games = try await Self.fetchGames(league: league, teamID: team.id)
                if settings.favoriteTeam?.id == team.id {
                    snapshot = SportsSnapshot.make(from: games, now: Date())
                    lastFetch = Date()
                }
                state = .idle
            } catch {
                state = .failed("Couldn't load scores.")
            }
            scheduleFollowUps()
        }
    }

    func loadTeams() {
        let league = settings.sportsLeague
        teamsState = .loading
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: ESPN.teamsURL(league))
                let list = try ESPN.teams(from: data)
                guard settings.sportsLeague == league else { return }
                teams = list
                teamsState = .idle
            } catch {
                teamsState = .failed("Couldn't load teams.")
            }
        }
    }

    func clearTeams() {
        teams = []
    }

    private static func fetchGames(league: SportsLeague, teamID: String) async throws -> [Game] {
        let (data, _) = try await URLSession.shared.data(from: ESPN.scheduleURL(league, teamID: teamID))
        var games = try ESPN.games(from: data)
        // Soccer schedules list results by default; upcoming fixtures need a second call.
        if league.isSoccer,
           let response = try? await URLSession.shared.data(from: ESPN.scheduleURL(league, teamID: teamID, fixtures: true)),
           let fixtures = try? ESPN.games(from: response.0) {
            games += fixtures
        }
        return ESPN.deduplicated(games)
    }

    private func scheduleFollowUps() {
        stopTimers()
        guard settings.isVisible(.sports), let game = snapshot?.featured else { return }
        switch game.state {
        case .live:
            liveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        case .pre:
            let delay = game.date.timeIntervalSinceNow
            guard delay < 24 * 3600, delay > -3600 else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            kickoffWork = work
            // Wall-clock deadline, so the timer survives the Mac sleeping.
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(delay, 0) + 30, execute: work)
        case .post:
            break
        }
    }

    private func stopTimers() {
        liveTimer?.invalidate()
        liveTimer = nil
        kickoffWork?.cancel()
        kickoffWork = nil
    }
}
