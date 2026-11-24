import SwiftUI

/// Small content on both sides of the notch while the island is closed.
struct ClosedActivityView: View {
    let activity: ClosedActivity
    let notchWidth: CGFloat
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var battery: BatteryService

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: activity.sideWidth)
            Spacer(minLength: notchWidth)
            trailing.frame(width: activity.sideWidth)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .nowPlaying:
            ArtworkView(image: nowPlaying.artwork, size: 22, cornerRadius: 6)
        case .charging:
            Text("Charging")
                .font(.system(size: 11, weight: .semibold))
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
                Text("\(battery.info?.percent ?? 0)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.green)
        case .none:
            EmptyView()
        }
    }
}

/// Animated equalizer bars shown while music plays.
struct AudioBars: View {
    private let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
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
