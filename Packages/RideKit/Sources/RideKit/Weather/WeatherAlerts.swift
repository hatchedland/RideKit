import Foundation

/// A weather alert while riding — passive, like the wishlist and famous-places alerts.
public struct WeatherAlert: Equatable, Sendable {
    /// In priority order: when several apply, the first one is announced.
    public enum Kind: String, CaseIterable, Sendable {
        case storm, rain, wind, heat, clearing, sunset
    }

    public var kind: Kind
    /// When it starts; `nil` means now.
    public var at: Date?
    /// Rain chance for `.rain` and `.storm`.
    public var percent: Int?
    /// Gust km/h (`.wind`), feels-like °C (`.heat`), meters still to ride (`.sunset`).
    public var value: Double?

    public init(kind: Kind, at: Date? = nil, percent: Int? = nil, value: Double? = nil) {
        self.kind = kind
        self.at = at
        self.percent = percent
        self.value = value
    }

    /// What and when, e.g. "Rain from 4:30 pm" — the card's first line.
    public func headline(time: (Date) -> String) -> String {
        let from = at.map { " from \(time($0))" }
        switch kind {
        case .storm: return "Thunderstorm" + (from ?? " likely now")
        case .rain: return "Rain" + (from ?? " now")
        case .wind: return "Strong gusts"
        case .heat: return "Feels like \(Int((value ?? 0).rounded()))°"
        case .clearing: return "Rain easing" + (from ?? " now")
        case .sunset: return at.map { "Sunset at \(time($0))" } ?? "Sunset soon"
        }
    }

    /// How much, or what to do — the card's quieter second line.
    public func detail(distance: (Double) -> String) -> String? {
        switch kind {
        case .storm: return "Find shelter"
        case .rain: return percent.map { "\($0)% chance" }
        case .wind: return "Up to \(Int((value ?? 0).rounded())) km/h"
        case .heat: return "Take a water break"
        case .clearing: return "Drier road ahead"
        case .sunset: return value.map { "\(distance($0)) to go" }
        }
    }

    /// Both lines in one, for the Lock Screen: "Rain from 4:30 pm · 80% chance".
    public func text(time: (Date) -> String, distance: (Double) -> String) -> String {
        [headline(time: time), detail(distance: distance)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// What has been announced this ride, so alerts fire on changes rather than repeating.
public struct WeatherAlertState: Equatable, Sendable {
    public var lastAlert: Date?
    public var lastByKind: [WeatherAlert.Kind: Date] = [:]
    /// A rain or storm alert was given and it hasn't cleared since.
    public var isWet = false

    public init() {}
}

/// Which weather alert to give, if any. Pure, so every rule is tested with fixed forecasts.
///
/// Rules: look at the hour now and the next 60 minutes; storm > rain > wind > heat > clearing;
/// rain is announced when it *starts* (dry → wet) and "easing" when it stops; the same kind at most
/// once an hour; any weather alert at most every 15 minutes. Sunset: once a ride, in the last 30
/// minutes of daylight while still ≥ 5 km from the destination.
public enum WeatherAlerts {
    public static let rainChance = 60
    /// A forecast that's wet by type ("LIGHT_RAIN") counts from this chance.
    public static let wetConditionRainChance = 40
    public static let thunderChance = 50
    public static let gustKmh: Double = 40
    public static let feelsLikeHeat: Double = 38
    public static let lookAhead: TimeInterval = 60 * 60
    public static let sameKindInterval: TimeInterval = 60 * 60
    public static let minimumInterval: TimeInterval = 15 * 60
    public static let sunsetWarning: TimeInterval = 30 * 60
    public static let sunsetMinimumRemaining: Double = 5_000

    public static func next(forecast: [WeatherHour], now: Date, state: inout WeatherAlertState) -> WeatherAlert? {
        let window = forecast
            .filter { $0.end > now && $0.start < now.addingTimeInterval(lookAhead) }
            .sorted { $0.start < $1.start }
        guard !window.isEmpty else { return nil }
        func startTime(_ hour: WeatherHour) -> Date? { hour.start > now ? hour.start : nil }

        var candidates: [WeatherAlert] = []
        let wetHours = window.filter { $0.isRainy || $0.isStormy }
        if let storm = window.first(where: \.isStormy) {
            candidates.append(WeatherAlert(kind: .storm, at: startTime(storm), percent: storm.rainChance))
        }
        if !state.isWet, let rain = wetHours.first {
            candidates.append(WeatherAlert(kind: .rain, at: startTime(rain), percent: rain.rainChance))
        }
        if let gust = window.compactMap(\.gustKmh).max(), gust >= gustKmh {
            candidates.append(WeatherAlert(kind: .wind, value: gust))
        }
        if let feels = window.compactMap(\.feelsLike).max(), feels >= feelsLikeHeat {
            candidates.append(WeatherAlert(kind: .heat, value: feels))
        }
        if state.isWet, let current = window.first, current.start <= now, current.isRainy || current.isStormy,
           let dry = window.dropFirst().first(where: { !$0.isRainy && !$0.isStormy }) {
            candidates.append(WeatherAlert(kind: .clearing, at: startTime(dry)))
        }
        if state.isWet, wetHours.isEmpty {
            // It cleared without us catching the hour it stopped; next rain is news again.
            state.isWet = false
        }

        let chosen = candidates.first { alert in
            state.lastByKind[alert.kind].map { now.timeIntervalSince($0) >= sameKindInterval } ?? true
        }
        guard let chosen, state.lastAlert.map({ now.timeIntervalSince($0) >= minimumInterval }) ?? true else { return nil }
        record(chosen, now: now, state: &state)
        return chosen
    }

    /// "Sunset at 6:12 pm · 48 km to go" once, in the last half hour of daylight with ≥ 5 km left.
    public static func sunset(_ sunset: Date?, now: Date, remainingMeters: Double?, state: inout WeatherAlertState) -> WeatherAlert? {
        guard let sunset, let remainingMeters, remainingMeters >= sunsetMinimumRemaining,
              now < sunset, sunset.timeIntervalSince(now) <= sunsetWarning,
              state.lastByKind[.sunset] == nil,
              state.lastAlert.map({ now.timeIntervalSince($0) >= minimumInterval }) ?? true else { return nil }
        let alert = WeatherAlert(kind: .sunset, at: sunset, value: remainingMeters)
        record(alert, now: now, state: &state)
        return alert
    }

    private static func record(_ alert: WeatherAlert, now: Date, state: inout WeatherAlertState) {
        state.lastAlert = now
        state.lastByKind[alert.kind] = now
        switch alert.kind {
        case .rain, .storm: state.isWet = true
        case .clearing: state.isWet = false
        default: break
        }
    }

    /// Before a ride: the one thing worth knowing about the next `hours` hours, most serious first
    /// (storm, rain, wind, heat), e.g. "Rain from 4 pm · 70% chance"; `nil` when it stays fine.
    public static func outlook(_ forecast: [WeatherHour], now: Date, hours: Double = 6) -> WeatherAlert? {
        let ahead = forecast
            .filter { $0.end > now && $0.start < now.addingTimeInterval(hours * 3_600) }
            .sorted { $0.start < $1.start }
        func at(_ hour: WeatherHour) -> Date? { hour.start > now ? hour.start : nil }
        if let storm = ahead.first(where: \.isStormy) {
            return WeatherAlert(kind: .storm, at: at(storm), percent: storm.rainChance)
        }
        if let rain = ahead.first(where: \.isRainy) {
            return WeatherAlert(kind: .rain, at: at(rain), percent: rain.rainChance)
        }
        if let gust = ahead.compactMap(\.gustKmh).max(), gust >= gustKmh {
            return WeatherAlert(kind: .wind, value: gust)
        }
        if let feels = ahead.compactMap(\.feelsLike).max(), feels >= feelsLikeHeat {
            return WeatherAlert(kind: .heat, value: feels)
        }
        return nil
    }

    /// The forecast hour covering `now`, for the riding screen's readout; `nil` without one.
    public static func current(_ forecast: [WeatherHour], now: Date) -> WeatherHour? {
        forecast.first { $0.start <= now && now < $0.end }
    }

    /// Where to ask for the forecast: about `seconds` of riding ahead along the route (the weather
    /// the rider is heading into), else where they are.
    public static func forecastPoint(from position: Coordinate, routeAhead: [Coordinate],
                                     speedMps: Double, seconds: TimeInterval = 30 * 60) -> Coordinate {
        let target = min(40_000, max(5_000, speedMps * seconds))
        guard routeAhead.count > 1 else { return position }
        var travelled = 0.0
        for (a, b) in zip(routeAhead, routeAhead.dropFirst()) {
            let step = a.distance(to: b)
            if travelled + step >= target {
                return a.interpolated(to: b, fraction: step > 0 ? (target - travelled) / step : 0)
            }
            travelled += step
        }
        return routeAhead.last ?? position
    }
}

/// Sunrise-equation sunset (accurate to a couple of minutes), so the sunset alert needs no request.
public enum Sun {
    /// Sunset on the day of the solar noon nearest `date`; `nil` in polar day or night.
    public static func sunset(near date: Date, at coordinate: Coordinate) -> Date? {
        let rad = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let east = coordinate.longitude / 360
        // Mean solar noon nearest `date`, in days since J2000.
        let noon = (julianDay - 2_451_545.0 + east).rounded() - east
        let anomaly = (357.5291 + 0.985_600_28 * noon).truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(anomaly * rad) + 0.02 * sin(2 * anomaly * rad) + 0.0003 * sin(3 * anomaly * rad)
        let longitude = (anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2_451_545.0 + noon + 0.0053 * sin(anomaly * rad) - 0.0069 * sin(2 * longitude * rad)
        let declination = asin(sin(longitude * rad) * sin(23.4397 * rad))
        let latitude = coordinate.latitude * rad
        let cosHourAngle = (sin(-0.833 * rad) - sin(latitude) * sin(declination)) / (cos(latitude) * cos(declination))
        guard (-1...1).contains(cosHourAngle) else { return nil }
        let set = transit + acos(cosHourAngle) / rad / 360
        return Date(timeIntervalSince1970: (set - 2_440_587.5) * 86_400)
    }
}
