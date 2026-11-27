import SwiftUI

/// Small content on both sides of the notch while the island is closed.
struct ClosedActivityView: View {
    let activity: ClosedActivity
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading.frame(width: activity.sideWidth)
                Spacer(minLength: vm.geometry.notchRect.width)
                trailing.frame(width: activity.sideWidth)
            }
            .frame(height: vm.geometry.notchRect.height)

            if vm.showsClosedLyrics {
                ClosedLyricLine(nowPlaying: vm.nowPlaying, lyrics: vm.lyrics)
                    .padding(.horizontal, 16)
                    .frame(height: NotchViewModel.closedLyricsHeight - 4)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .nowPlaying:
            ArtworkView(image: vm.nowPlaying.artwork, size: 22, cornerRadius: 6)
        case .charging:
            Text("Charging")
        case .liveScore:
            if let game = vm.sports.snapshot?.featured {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("\(game.away.team.shortLabel) \(game.away.score ?? "0")")
                        .compatMonospacedDigit()
                        .lineLimit(1)
                }
            }
        case .upcomingEvent:
            if let event = vm.calendar.headsUp {
                HStack(spacing: 4) {
                    Circle().fill(event.color).frame(width: 5, height: 5)
                    Text(event.title)
                        .lineLimit(1)
                }
                .padding(.leading, 6)
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity {
        case .nowPlaying:
            AudioBars()
                .frame(width: 18, height: 14)
        case .charging:
            HStack(spacing: 3) {
                Text("\(vm.battery.info?.percent ?? 0)%")
                    .compatMonospacedDigit()
                SymbolImage("bolt.fill")
                    .font(.system(size: 10))
            }
            .foregroundColor(.green)
        case .liveScore:
            if let game = vm.sports.snapshot?.featured {
                Text("\(game.home.score ?? "0") \(game.home.team.shortLabel)")
                    .compatMonospacedDigit()
                    .lineLimit(1)
            }
        case .upcomingEvent:
            if let event = vm.calendar.headsUp {
                Ticker(every: 30) { context in
                    Text(RelativeTime.countdown(to: event.start, from: context.date))
                }
                .foregroundColor(.orange)
            }
        case .none:
            EmptyView()
        }
    }
}

/// Animated equalizer bars shown while music plays.
struct AudioBars: View {
    private let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]

    var body: some View {
        Ticker(every: 1.0 / 24) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(speeds.indices, id: \.self) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: 14 * (0.3 + 0.7 * abs(sin(t * speeds[index] + Double(index)))))
                }
            }
            .frame(height: 14)
        }
    }
}
