import Foundation
import OSLog
import RideKit

/// Sends Google Places requests (built and parsed in RideKit's `GooglePlaces`) with the app's
/// Google Maps key. Every failure (offline, no key, quota, refused key) comes back as "no places",
/// so a spot is still saved instantly and just keeps its fallback name.
struct GooglePlacesClient: Sendable {
    let apiKey: String?
    let bundleID: String
    static let log = Logger(subsystem: "com.hatchedland.ridetracker", category: "places")

    @MainActor
    static var app: GooglePlacesClient {
        GooglePlacesClient(apiKey: GoogleMapsSetup.apiKey, bundleID: Bundle.main.bundleIdentifier ?? "com.hatchedland.ridetracker")
    }

    private var languageCode: String { Locale.current.language.languageCode?.identifier ?? "en" }

    /// Places within `radius` meters, nearest first.
    func nearby(_ coordinate: Coordinate, radius: Double) async -> [Place] {
        guard let apiKey else { return [] }
        return await send(GooglePlaces.nearbyRequest(around: coordinate, radius: radius,
                                                     apiKey: apiKey, bundleID: bundleID, languageCode: languageCode))
    }

    /// The most popular sights within `radius` meters, with ratings (famous places ahead).
    func famous(near coordinate: Coordinate, radius: Double) async -> [Place] {
        guard let apiKey else { return [] }
        return await send(GooglePlaces.famousRequest(around: coordinate, radius: radius,
                                                     apiKey: apiKey, bundleID: bundleID, languageCode: languageCode))
    }

    /// Places matching `query`, preferring ones near `near`.
    func search(_ query: String, near: Coordinate?) async -> [Place] {
        guard let apiKey else { return [] }
        return await send(GooglePlaces.textRequest(query, near: near,
                                                   apiKey: apiKey, bundleID: bundleID, languageCode: languageCode))
    }

    private func send(_ request: URLRequest) async -> [Place] {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                Self.log.error("Places request failed: \(GooglePlaces.error(status: status, data: data).message, privacy: .public)")
                return []
            }
            return try GooglePlaces.places(from: data)
        } catch is CancellationError {
            return []
        } catch {
            Self.log.notice("Places unavailable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension GooglePlacesClient {
    /// A two-wheeler route from Google's Routes API (same key); `nil` offline or on any failure,
    /// in which case the ride falls back to the straight-line distance.
    func route(from origin: Coordinate, to destination: Coordinate) async -> RideRoute? {
        guard let apiKey else { return nil }
        let request = GoogleRoutes.request(from: origin, to: destination, apiKey: apiKey, bundleID: bundleID,
                                           languageCode: Locale.current.language.languageCode?.identifier ?? "en")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try GoogleRoutes.route(from: data)
        } catch {
            return nil
        }
    }
}

extension GooglePlacesClient {
    /// The next 3 hours of Google Weather at `coordinate`; empty offline or on any failure (the ride
    /// just gets no weather alerts). Debug builds launched with `-fakeWeather rain|rainSoon|storm|wind|heat|clearing|sunny|night|cloudy|sunset`
    /// get a made-up forecast instead, to see each alert in the simulator.
    func forecastHours(at coordinate: Coordinate) async -> [WeatherHour] {
        #if DEBUG
        if let fake = UserDefaults.standard.string(forKey: "fakeWeather") { return FakeWeather.hours(fake, now: .now) }
        #endif
        guard let apiKey else { return [] }
        let request = GoogleWeather.hoursRequest(at: coordinate, apiKey: apiKey, bundleID: bundleID,
                                                 languageCode: Locale.current.language.languageCode?.identifier ?? "en")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                Self.log.error("Weather request failed: \(GooglePlaces.error(status: status, data: data).message, privacy: .public)")
                return []
            }
            return try GoogleWeather.hours(from: data)
        } catch {
            return []
        }
    }
}

#if DEBUG
/// `-fakeWeather <kind>`: a forecast that triggers that alert on the first check of a ride.
enum FakeWeather {
    static func hours(_ kind: String, now: Date) -> [WeatherHour] {
        let current = now.addingTimeInterval(-20 * 60), next = now.addingTimeInterval(40 * 60)
        switch kind {
        case "rain":
            // Raining now: the rain behind the numbers, and "Rain now · 85% chance".
            return [WeatherHour(start: current, condition: "RAIN", temperature: 21, rainChance: 85, isDaytime: true),
                    WeatherHour(start: next, condition: "RAIN", temperature: 20, rainChance: 80, isDaytime: true)]
        case "rainSoon":
            return [WeatherHour(start: current, condition: "CLOUDY", temperature: 23, rainChance: 20, isDaytime: true),
                    WeatherHour(start: next, condition: "RAIN", temperature: 21, rainChance: 80, isDaytime: true)]
        case "sunny":
            return [WeatherHour(start: current, condition: "CLEAR", temperature: 27, feelsLike: 28, isDaytime: true)]
        case "night":
            return [WeatherHour(start: current, condition: "CLEAR", temperature: 18, isDaytime: false)]
        case "cloudy":
            return [WeatherHour(start: current, condition: "MOSTLY_CLOUDY", temperature: 22, isDaytime: true)]
        case "storm":
            return [WeatherHour(start: current, condition: "THUNDERSTORM", temperature: 24, rainChance: 85, thunderChance: 70, isDaytime: true),
                    WeatherHour(start: next, condition: "THUNDERSTORM", temperature: 23, rainChance: 85, thunderChance: 70, isDaytime: true)]
        case "wind":
            return [WeatherHour(start: current, condition: "WINDY", temperature: 19, gustKmh: 48, isDaytime: true)]
        case "heat":
            return [WeatherHour(start: current, condition: "CLEAR", temperature: 37, feelsLike: 41, isDaytime: true)]
        case "clearing":
            // Rain now (first alert), easing in 40 min (second alert, 15 min later).
            return [WeatherHour(start: current, condition: "RAIN", rainChance: 85),
                    WeatherHour(start: next, condition: "MOSTLY_CLOUDY", rainChance: 15)]
        default:
            return []
        }
    }
}
#endif
