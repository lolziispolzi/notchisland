import SwiftUI

struct SportsView: View {
    @ObservedObject var vm: NotchViewModel

    private var sports: SportsService { vm.sports }

    var body: some View {
        if let team = vm.settings.favoriteTeam {
            if let snapshot = sports.snapshot {
                if let game = snapshot.featured {
                    HStack(alignment: .center, spacing: 16) {
                        GameCard(game: game)
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1)
                            .padding(.vertical, 6)
                        GameList(snapshot: snapshot, teamID: team.id)
                    }
                } else {
                    WidgetMessage(symbol: vm.settings.sportsLeague.symbol,
                                  title: "No games scheduled",
                                  message: "\(team.name) has no recent or upcoming games.")
                }
            } else if let error = sports.state.errorMessage {
                WidgetMessage(symbol: "exclamationmark.icloud",
                              title: error,
                              buttonTitle: "Try Again",
                              action: { sports.refresh() })
            } else {
                Spinner()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            WidgetMessage(symbol: "sportscourt",
                          title: "Follow your team",
                          message: "Search for your team to see live scores and every upcoming game.",
                          buttonTitle: "Choose Team…",
                          action: vm.openSettings)
        }
    }
}

private struct GameCard: View {
    let game: Game

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                TeamColumn(side: game.away)
                if game.state == .pre {
                    Text("vs")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("\(game.away.score ?? "0")  –  \(game.home.score ?? "0")")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .compatMonospacedDigit()
                }
                TeamColumn(side: game.home)
            }
            StatusLabel(game: game)
            if let competition = game.competition {
                Text(competition)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }
}

private struct TeamColumn: View {
    let side: TeamSide

    var body: some View {
        VStack(spacing: 4) {
            TeamLogo(urlString: side.team.logoURL, size: 38)
            Text(side.team.shortLabel)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .frame(width: 56)
    }
}

struct TeamLogo: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        RemoteImage(url: urlString.flatMap(URL.init(string:)), contentMode: .fit) {
            Circle().fill(Color.white.opacity(0.1))
        }
        .frame(width: size, height: size)
    }
}

private struct StatusLabel: View {
    let game: Game

    var body: some View {
        Group {
            switch game.state {
            case .live:
                HStack(spacing: 5) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text(game.detail.isEmpty ? "Live" : game.detail)
                }
            case .pre:
                Text(DateText.string(game.date, template: "EEEMMMdjmm"))
            case .post:
                Text(game.detail.isEmpty ? "Final" : game.detail)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.7))
    }
}

private struct GameList: View {
    let snapshot: SportsSnapshot
    let teamID: String

    private var showsUpcoming: Bool { !snapshot.upcoming.isEmpty }
    private var games: [Game] { showsUpcoming ? snapshot.upcoming : snapshot.recent }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showsUpcoming ? "UPCOMING" : "RECENT")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
            ForEach(games) { game in
                GameRow(game: game, teamID: teamID)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GameRow: View {
    let game: Game
    let teamID: String

    private var opponentLabel: String {
        guard let mine = game.side(of: teamID), let other = game.opponent(of: teamID) else {
            return "\(game.away.team.shortLabel) @ \(game.home.team.shortLabel)"
        }
        return mine.isHome ? "vs \(other.team.shortLabel)" : "@ \(other.team.shortLabel)"
    }

    var body: some View {
        HStack(spacing: 6) {
            TeamLogo(urlString: game.opponent(of: teamID)?.team.logoURL, size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(opponentLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let competition = game.competition {
                    Text(competition)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let result = game.result(for: teamID),
           let mine = game.side(of: teamID)?.score,
           let theirs = game.opponent(of: teamID)?.score {
            Text("\(result) \(mine)–\(theirs)")
                .foregroundColor(result == "W" ? Color.green : (result == "L" ? Color.red : Color.white.opacity(0.7)))
                .compatMonospacedDigit()
        } else {
            Text(DateText.string(game.date, template: "EEEjmm"))
                .foregroundColor(.white.opacity(0.55))
        }
    }
}
