import Combine
import CoreLocation
import Foundation

struct WeatherLocation: Codable, Equatable, Hashable {
    var name: String
    /// Region and country, e.g. "England, United Kingdom".
    var detail: String?
    var latitude: Double
    var longitude: Double
}

struct WeatherSnapshot: Equatable {
    struct Day: Equatable, Identifiable {
        var date: Date
        var code: Int
        var high: Double
        var low: Double
        var precipitationChance: Int?
        var id: Date { date }
    }

    var locationName: String
    var unit: TemperatureUnit
    var temperature: Double
    var feelsLike: Double
    var code: Int
    var isDay: Bool
    var humidity: Int
    var windSpeed: Double
    var days: [Day]
}

/// WMO weather interpretation codes, as returned by Open-Meteo.
enum WeatherCode {
    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 61...67, 80...81: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71...75, 77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "Unknown"
        }
    }
}

/// Open-Meteo: free weather API, no key needed. https://open-meteo.com
enum OpenMeteo {
    struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let apparentTemperature: Double
            let weatherCode: Int
            let isDay: Int
            let windSpeed: Double
            let humidity: Double

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case weatherCode = "weather_code"
                case isDay = "is_day"
                case windSpeed = "wind_speed_10m"
                case humidity = "relative_humidity_2m"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let high: [Double]
            let low: [Double]
            let precipitationChance: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case high = "temperature_2m_max"
                case low = "temperature_2m_min"
                case precipitationChance = "precipitation_probability_max"
            }
        }

        let current: Current
        let daily: Daily
    }

    struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }

        let results: [Result]?
    }

    static func forecastURL(latitude: Double, longitude: Double, unit: TemperatureUnit) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "wind_speed_unit", value: unit.windUnit),
        ]
        return components.url!
    }

    static func geocodingURL(query: String) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    static func snapshot(from data: Data, locationName: String, unit: TemperatureUnit) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let daily = response.daily
        var days: [WeatherSnapshot.Day] = []
        for (index, string) in daily.time.enumerated() {
            guard let date = formatter.date(from: string),
                  index < daily.weatherCode.count, index < daily.high.count, index < daily.low.count
            else { continue }
            let chance = daily.precipitationChance.flatMap { index < $0.count ? $0[index] : nil }
            days.append(WeatherSnapshot.Day(date: date,
                                            code: daily.weatherCode[index],
                                            high: daily.high[index],
                                            low: daily.low[index],
                                            precipitationChance: chance.map { Int($0.rounded()) }))
        }

        let current = response.current
        return WeatherSnapshot(locationName: locationName,
                               unit: unit,
                               temperature: current.temperature,
                               feelsLike: current.apparentTemperature,
                               code: current.weatherCode,
                               isDay: current.isDay != 0,
                               humidity: Int(current.humidity.rounded()),
                               windSpeed: current.windSpeed,
                               days: days)
    }

    static func locations(from data: Data) throws -> [WeatherLocation] {
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map { result in
            let detail = [result.admin1, result.country].compactMap { $0 }.joined(separator: ", ")
            return WeatherLocation(name: result.name,
                                   detail: detail.isEmpty ? nil : detail,
                                   latitude: result.latitude,
                                   longitude: result.longitude)
        }
    }
}

/// Loads the forecast for the current location, or the city picked in Settings.
/// Fetches only when the island opens and the data is older than 15 minutes.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var state: LoadState = .idle
    /// No location: current location is off or denied, and no city is set.
    @Published private(set) var needsLocation = false

    static let staleAfter: TimeInterval = 15 * 60

    private let settings: AppSettings
    private let locator = LocationProvider()
    private var lastFetch: Date?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings

        Publishers.Merge3(
            settings.$temperatureUnit.dropFirst().map { _ in () },
            settings.$useCurrentLocation.dropFirst().map { _ in () },
            settings.$manualLocation.dropFirst().map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.invalidate() }
        .store(in: &cancellables)
    }

    func invalidate() {
        lastFetch = nil
        if snapshot != nil || needsLocation { refresh() }
    }

    func refreshIfStale() {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < Self.staleAfter { return }
        refresh()
    }

    func refresh() {
        guard state != .loading else { return }
        state = .loading
        Task {
            guard let location = await resolveLocation() else {
                needsLocation = true
                state = .idle
                return
            }
            needsLocation = false
            do {
                let unit = settings.temperatureUnit
                let url = OpenMeteo.forecastURL(latitude: location.latitude, longitude: location.longitude, unit: unit)
                let (data, _) = try await URLSession.shared.data(from: url)
                snapshot = try OpenMeteo.snapshot(from: data, locationName: location.name, unit: unit)
                lastFetch = Date()
                state = .idle
            } catch {
                state = .failed("Couldn't load the weather.")
            }
        }
    }

    static func searchLocations(_ query: String) async throws -> [WeatherLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let (data, _) = try await URLSession.shared.data(from: OpenMeteo.geocodingURL(query: trimmed))
        return try OpenMeteo.locations(from: data)
    }

    private func resolveLocation() async -> WeatherLocation? {
        if settings.useCurrentLocation, AppEnvironment.isBundled,
           let location = await locator.currentLocation() {
            let name = await Self.placeName(for: location) ?? "Current Location"
            return WeatherLocation(name: name,
                                   detail: nil,
                                   latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude)
        }
        return settings.manualLocation
    }

    private static func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.locality ?? placemarks?.first?.name
    }
}

/// One-shot location lookups with CoreLocation, wrapped as async.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutWork: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    private var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Returns nil when access is denied, the lookup fails, or it takes over 20 seconds.
    func currentLocation() async -> CLLocation? {
        guard continuation == nil, !isDenied else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                // The location is requested once the user answers the prompt.
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.finish(nil) }
            }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
        }
    }

    private func finish(_ location: CLLocation?) {
        timeoutWork?.cancel()
        timeoutWork = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated { finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .notDetermined:
                break
            case .denied, .restricted:
                finish(nil)
            default:
                self.manager.requestLocation()
            }
        }
    }
}
