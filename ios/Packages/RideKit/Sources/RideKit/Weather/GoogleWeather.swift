import Foundation

/// One hour of Google's forecast, reduced to what ride alerts need. Metric throughout.
public struct WeatherHour: Equatable, Sendable {
    /// Start of the hour (Google's hours can start on the half hour).
    public var start: Date
    /// Google's condition type, e.g. "LIGHT_RAIN" or "THUNDERSTORM".
    public var condition: String
    public var temperature: Double?
    public var feelsLike: Double?
    /// Chance of rain (or other precipitation), 0–100.
    public var rainChance: Int
    public var thunderChance: Int
    public var gustKmh: Double?
    /// Google's day/night flag; `nil` if not sent.
    public var isDaytime: Bool?

    public init(start: Date, condition: String = "CLEAR", temperature: Double? = nil, feelsLike: Double? = nil,
                rainChance: Int = 0, thunderChance: Int = 0, gustKmh: Double? = nil, isDaytime: Bool? = nil) {
        self.start = start
        self.condition = condition
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.rainChance = rainChance
        self.thunderChance = thunderChance
        self.gustKmh = gustKmh
        self.isDaytime = isDaytime
    }

    public var end: Date { start.addingTimeInterval(3_600) }

    private var isWetCondition: Bool {
        ["RAIN", "SHOWER", "THUNDER", "HAIL", "SLEET", "SNOW"].contains { condition.contains($0) }
    }

    /// Worth getting the rain gear out for: likely, or forecast as wet with a fair chance.
    public var isRainy: Bool {
        rainChance >= WeatherAlerts.rainChance || (isWetCondition && rainChance >= WeatherAlerts.wetConditionRainChance)
    }

    public var isStormy: Bool {
        thunderChance >= WeatherAlerts.thunderChance || condition.contains("THUNDER") || condition.contains("HAIL")
    }

    /// What the sky is doing this hour, for the riding screen's readout and backdrop. Most
    /// important first: a stormy, windy hour is a storm.
    public var sky: WeatherSky {
        if isStormy { return .storm }
        if isRainy { return .rain }
        if (gustKmh ?? 0) >= WeatherAlerts.gustKmh { return .wind }
        if (feelsLike ?? 0) >= WeatherAlerts.feelsLikeHeat { return .heat }
        if ["CLOUDY", "FOG", "OVERCAST"].contains(where: { condition.contains($0) }) && !condition.contains("MOSTLY_CLEAR") {
            return condition.contains("PARTLY") ? .partlyCloudy : .cloudy
        }
        return .clear
    }
}

/// The weather at a glance while riding.
public enum WeatherSky: String, Sendable, CaseIterable {
    case clear, partlyCloudy, cloudy, rain, storm, wind, heat
}

/// Google Weather API: the hourly forecast request, and reading its answer. Same iOS key and
/// bundle-id header as Places; `GooglePlacesClient` in the app sends it.
public enum GoogleWeather {
    public static let hoursURL = URL(string: "https://weather.googleapis.com/v1/forecast/hours:lookup")!

    /// The next `hours` hours at `coordinate`, metric.
    public static func hoursRequest(at coordinate: Coordinate, hours: Int = 3, apiKey: String, bundleID: String,
                                    languageCode: String = "en") -> URLRequest {
        var components = URLComponents(url: hoursURL, resolvingAgainstBaseURL: false)!
        let count = max(1, min(24, hours))
        components.queryItems = [
            URLQueryItem(name: "location.latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "location.longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "hours", value: "\(count)"),
            URLQueryItem(name: "pageSize", value: "\(count)"),
            URLQueryItem(name: "unitsSystem", value: "METRIC"),
            URLQueryItem(name: "languageCode", value: languageCode),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        return request
    }

    private struct Response: Decodable {
        struct Hour: Decodable {
            struct Interval: Decodable { var startTime: String? }
            struct Condition: Decodable { var type: String? }
            struct Temperature: Decodable { var degrees: Double?; var unit: String? }
            struct Probability: Decodable { var percent: Int? }
            struct Precipitation: Decodable { var probability: Probability? }
            struct Speed: Decodable { var value: Double?; var unit: String? }
            struct Wind: Decodable { var gust: Speed?; var speed: Speed? }
            var interval: Interval?
            var weatherCondition: Condition?
            var temperature: Temperature?
            var feelsLikeTemperature: Temperature?
            var precipitation: Precipitation?
            var thunderstormProbability: Int?
            var wind: Wind?
            var isDaytime: Bool?
        }
        var forecastHours: [Hour]?
    }

    /// Hours from a response body, in time order; hours without a valid start time are skipped.
    public static func hours(from data: Data) throws -> [WeatherHour] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let iso = ISO8601DateFormatter()
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (response.forecastHours ?? []).compactMap { hour in
            guard let text = hour.interval?.startTime,
                  let start = iso.date(from: text) ?? isoFraction.date(from: text) else { return nil }
            return WeatherHour(
                start: start,
                condition: hour.weatherCondition?.type ?? "TYPE_UNSPECIFIED",
                temperature: celsius(hour.temperature),
                feelsLike: celsius(hour.feelsLikeTemperature),
                rainChance: hour.precipitation?.probability?.percent ?? 0,
                thunderChance: hour.thunderstormProbability ?? 0,
                gustKmh: kmh(hour.wind?.gust) ?? kmh(hour.wind?.speed),
                isDaytime: hour.isDaytime
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func celsius(_ t: Response.Hour.Temperature?) -> Double? {
        guard let degrees = t?.degrees else { return nil }
        return t?.unit == "FAHRENHEIT" ? (degrees - 32) * 5 / 9 : degrees
    }

    private static func kmh(_ s: Response.Hour.Speed?) -> Double? {
        guard let value = s?.value else { return nil }
        return s?.unit == "MILES_PER_HOUR" ? value * 1.609_344 : value
    }
}
