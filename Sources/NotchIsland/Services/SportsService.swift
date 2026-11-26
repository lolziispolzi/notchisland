import Combine
import Foundation

enum SportsLeague: String, CaseIterable, Identifiable, Codable {
    case nfl, nba, wnba, mlb, nhl
    case mls, premierLeague, laLiga, bundesliga, serieA, ligue1, championsLeague
    case championship, eredivisie, primeiraLiga, scottishPremiership, saudiProLeague, ligaMX, brasileirao
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
        case .championship: "EFL Championship"
        case .eredivisie: "Eredivisie"
        case .primeiraLiga: "Primeira Liga"
        case .scottishPremiership: "Scottish Premiership"
        case .saudiProLeague: "Saudi Pro League"
        case .ligaMX: "Liga MX"
        case .brasileirao: "Brasileirão"
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
        case .championship: "soccer/eng.2"
        case .eredivisie: "soccer/ned.1"
        case .primeiraLiga: "soccer/por.1"
        case .scottishPremiership: "soccer/sco.1"
        case .saudiProLeague: "soccer/ksa.1"
        case .ligaMX: "soccer/mex.1"
        case .brasileirao: "soccer/bra.1"
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
    /// The league the team was found in. Nil for teams saved by older versions.
    var league: SportsLeague?

    var shortLabel: String { abbreviation.isEmpty ? name : abbreviation }

    /// Unique across leagues: the same number can mean different teams in different sports.
    var searchKey: String { "\(league?.rawValue ?? "")/\(id)" }
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
    /// Competition name, e.g. "Premier League", "UEFA Champions League". Nil when ESPN doesn't say.
    var competition: String? = nil

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

    /// Every schedule a team's games can be in.
    ///
    /// Soccer clubs play in several competitions (league, domestic cups, European cups,
    /// friendlies). ESPN's "all" endpoint lists them all for one club ID: results by
    /// default, upcoming fixtures with `fixture=true`. Other sports have one league,
    /// plus a separate list for the playoffs (season type 3).
    static func scheduleURLs(for league: SportsLeague, teamID: String) -> [URL] {
        if league.isSoccer {
            let all = base + "soccer/all/teams/\(teamID)/schedule"
            return [URL(string: all)!, URL(string: all + "?fixture=true")!]
        }
        let path = base + league.path + "/teams/\(teamID)/schedule"
        return [URL(string: path)!, URL(string: path + "?seasontype=3")!]
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
        struct League: Decodable {
            let abbreviation: String?
            let shortName: String?
            let name: String?
        }
        let id: String
        let date: String?
        let competitions: [Competition]?
        let league: League?
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

    static func teams(from data: Data, league: SportsLeague? = nil) throws -> [SavedTeam] {
        let response = try JSONDecoder().decode(TeamsResponse.self, from: data)
        let teams = response.sports?.first?.leagues?.first?.teams?.map { wrapper -> SavedTeam in
            var team = wrapper.team.saved
            team.league = league
            return team
        } ?? []
        return teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Teams whose name or abbreviation matches the query, best matches first.
    static func search(_ query: String, in teams: [SavedTeam], limit: Int = 25) -> [SavedTeam] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        func rank(_ team: SavedTeam) -> Int? {
            let name = team.name.lowercased()
            if team.abbreviation.lowercased() == needle || name == needle { return 0 }
            if name.hasPrefix(needle) { return 1 }
            if name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 2 }
            if name.contains(needle) { return 3 }
            return nil
        }
        return teams
            .compactMap { team in rank(team).map { (team, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }
            .prefix(limit)
            .map { $0.0 }
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
                    away: TeamSide(team: awayTeam, score: away.score?.display, isHome: false),
                    competition: event.league?.abbreviation ?? event.league?.shortName ?? event.league?.name)
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
    /// Teams of every supported league, for searching in Settings.
    @Published private(set) var allTeams: [SavedTeam] = []
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
        let league = team.league ?? settings.sportsLeague
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

    /// Loads the team lists of every league once, for search.
    func loadAllTeams() {
        guard allTeams.isEmpty, teamsState != .loading else { return }
        teamsState = .loading
        Task {
            let lists = await withTaskGroup(of: [SavedTeam].self) { group in
                for league in SportsLeague.allCases {
                    group.addTask {
                        guard let result = try? await URLSession.shared.data(from: ESPN.teamsURL(league)) else { return [] }
                        return (try? ESPN.teams(from: result.0, league: league)) ?? []
                    }
                }
                var all: [[SavedTeam]] = []
                for await list in group { all.append(list) }
                return all
            }
            // A club in two leagues we list (say, the Premier League and the Champions League)
            // appears once, under its domestic league.
            var seen = Set<String>()
            var merged: [SavedTeam] = []
            for team in lists.flatMap({ $0 }).sorted(by: { ($0.league == .championsLeague ? 1 : 0) < ($1.league == .championsLeague ? 1 : 0) }) {
                let sport = team.league?.sportName ?? ""
                if seen.insert("\(sport)/\(team.id)").inserted { merged.append(team) }
            }
            allTeams = merged
            teamsState = merged.isEmpty ? .failed("Couldn't load teams.") : .idle
        }
    }

    func search(_ query: String) -> [SavedTeam] {
        ESPN.search(query, in: allTeams)
    }

    private static func fetchGames(league: SportsLeague, teamID: String) async throws -> [Game] {
        var games: [Game] = []
        var anySucceeded = false
        for url in ESPN.scheduleURLs(for: league, teamID: teamID) {
            guard let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let parsed = try? ESPN.games(from: result.0)
            else { continue }
            anySucceeded = true
            games += parsed
        }
        guard anySucceeded else { throw URLError(.badServerResponse) }
        // Games without a competition name are in the team's own league.
        return ESPN.deduplicated(games).map { game in
            var game = game
            if game.competition == nil { game.competition = league.title }
            return game
        }
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
