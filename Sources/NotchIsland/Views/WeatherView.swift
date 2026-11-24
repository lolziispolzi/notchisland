import SwiftUI

struct WeatherView: View {
    @ObservedObject var vm: NotchViewModel

    private var weather: WeatherService { vm.weather }

    var body: some View {
        if let snapshot = weather.snapshot {
            HStack(alignment: .center, spacing: 18) {
                CurrentWeather(snapshot: snapshot)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    ForEach(Array(snapshot.days.prefix(5).enumerated()), id: \.element.id) { index, day in
                        DayColumn(day: day, isToday: index == 0)
                    }
                }
            }
        } else if weather.needsLocation {
            WidgetMessage(symbol: "location.slash",
                          title: "No location",
                          message: "Allow location access, or pick a city in Settings.",
                          buttonTitle: "Open Settings",
                          action: vm.openSettings)
        } else if let error = weather.state.errorMessage {
            WidgetMessage(symbol: "exclamationmark.icloud",
                          title: error,
                          buttonTitle: "Try Again",
                          action: { weather.refresh() })
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CurrentWeather: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                Text(snapshot.locationName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.7))

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WeatherCode.symbol(for: snapshot.code, isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 32))
                Text(Temperature.string(snapshot.temperature))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
            }

            Text(WeatherCode.description(for: snapshot.code))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            Text("Feels \(Temperature.string(snapshot.feelsLike)) · \(snapshot.humidity)% · \(Int(snapshot.windSpeed.rounded())) \(snapshot.unit.windLabel)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct DayColumn: View {
    let day: WeatherSnapshot.Day
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Image(systemName: WeatherCode.symbol(for: day.code))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 16))
                .frame(height: 20)
            Text(Temperature.string(day.high))
                .font(.system(size: 12, weight: .semibold))
            Text(Temperature.string(day.low))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            if let chance = day.precipitationChance, chance >= 20 {
                Text("\(chance)%")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
        }
        .frame(width: 42)
    }
}

enum Temperature {
    /// "21°"
    static func string(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}
