import Foundation
import Testing
@testable import RideKit

@Suite("Weather alerts")
struct WeatherTests {
    /// 16:10 UTC; forecast hours start on the half hour like Google's.
    let now = ISO8601DateFormatter().date(from: "2026-11-17T16:10:00Z")!
    var hourStart: Date { now.addingTimeInterval(-40 * 60) }

    func hour(_ offset: Int, _ condition: String = "CLEAR", rain: Int = 0, thunder: Int = 0,
              feels: Double? = 28, gust: Double? = 10) -> WeatherHour {
        WeatherHour(start: hourStart.addingTimeInterval(Double(offset) * 3_600), condition: condition,
                    temperature: feels, feelsLike: feels, rainChance: rain, thunderChance: thunder, gustKmh: gust)
    }

    func text(_ alert: WeatherAlert?) -> String? {
        let time = DateFormatter()
        time.timeZone = TimeZone(identifier: "UTC")
        time.dateFormat = "HH:mm"
        return alert?.text(time: { time.string(from: $0) }, distance: { String(format: "%.0f km", $0 / 1_000) })
    }

    // MARK: Parsing

    @Test func parsesGoogleHours() throws {
        let json = """
        {"forecastHours":[
          {"interval":{"startTime":"2026-11-17T07:30:00Z","endTime":"2026-11-17T08:30:00Z"},
           "weatherCondition":{"type":"LIGHT_RAIN"},"temperature":{"degrees":80.6,"unit":"FAHRENHEIT"},
           "feelsLikeTemperature":{"degrees":27.8,"unit":"CELSIUS"},
           "precipitation":{"probability":{"type":"RAIN","percent":45},"qpf":{"quantity":0.4,"unit":"MILLIMETERS"}},
           "thunderstormProbability":10,"wind":{"speed":{"value":12,"unit":"KILOMETERS_PER_HOUR"},"gust":{"value":20,"unit":"MILES_PER_HOUR"}}},
          {"interval":{"startTime":"2026-11-17T06:30:00Z"},"weatherCondition":{"type":"MOSTLY_CLOUDY"},"isDaytime":true,
           "precipitation":{"probability":{"percent":10}},"wind":{"speed":{"value":8,"unit":"KILOMETERS_PER_HOUR"}}},
          {"interval":{},"weatherCondition":{"type":"CLEAR"}}
        ]}
        """
        let hours = try GoogleWeather.hours(from: Data(json.utf8))
        #expect(hours.count == 2)
        #expect(hours[0].condition == "MOSTLY_CLOUDY")   // sorted by time
        #expect(hours[0].gustKmh == 8)                    // falls back to wind speed
        #expect(hours[0].isDaytime == true && hours[1].isDaytime == nil)
        #expect(hours[1].condition == "LIGHT_RAIN")
        #expect(abs((hours[1].temperature ?? 0) - 27) < 0.01)
        #expect(hours[1].feelsLike == 27.8)
        #expect(hours[1].rainChance == 45 && hours[1].thunderChance == 10)
        #expect(abs((hours[1].gustKmh ?? 0) - 32.19) < 0.01)
        #expect(hours[1].isRainy)                         // wet type + 45 %
        #expect(try GoogleWeather.hours(from: Data("{}".utf8)).isEmpty)
    }

    @Test func requestUsesKeyHeadersAndMetric() throws {
        let request = GoogleWeather.hoursRequest(at: Coordinate(latitude: 12.42, longitude: 75.74), apiKey: "K", bundleID: "b")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "K")
        #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "b")
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["location.latitude"] == "12.42000" && query["location.longitude"] == "75.74000")
        #expect(query["unitsSystem"] == "METRIC" && query["hours"] == "3")
        #expect(request.url?.absoluteString.hasPrefix("https://weather.googleapis.com/v1/forecast/hours:lookup?") == true)
    }

    @Test func rainAndStormThresholds() {
        #expect(hour(0, rain: 60).isRainy)
        #expect(!hour(0, rain: 59).isRainy)
        #expect(hour(0, "LIGHT_RAIN", rain: 40).isRainy)
        #expect(!hour(0, "CHANCE_OF_SHOWERS", rain: 30).isRainy)
        #expect(hour(0, thunder: 50).isStormy)
        #expect(hour(0, "SCATTERED_THUNDERSTORMS", rain: 20).isStormy)
        #expect(!hour(0, "RAIN", rain: 90).isStormy)
    }

    @Test func skyAtAGlance() {
        #expect(hour(0).sky == .clear)
        #expect(hour(0, "PARTLY_CLOUDY").sky == .partlyCloudy)
        #expect(hour(0, "MOSTLY_CLOUDY").sky == .cloudy)
        #expect(hour(0, "FOG").sky == .cloudy)
        #expect(hour(0, "RAIN", rain: 80).sky == .rain)
        #expect(hour(0, "THUNDERSTORM", rain: 80, gust: 60).sky == .storm)
        #expect(hour(0, gust: 45).sky == .wind)
        #expect(hour(0, feels: 39).sky == .heat)
        #expect(hour(0, "CHANCE_OF_SHOWERS", rain: 30).sky == .clear)
    }

    @Test func currentHourCoversNow() {
        let forecast = [hour(0), hour(1, "RAIN", rain: 80)]
        #expect(WeatherAlerts.current(forecast, now: now)?.condition == "CLEAR")
        #expect(WeatherAlerts.current(forecast, now: now.addingTimeInterval(30 * 60))?.condition == "RAIN")
        #expect(WeatherAlerts.current(forecast, now: now.addingTimeInterval(3 * 3_600)) == nil)
    }

    // MARK: Alerts

    @Test func quietOnAClearDay() {
        var state = WeatherAlertState()
        #expect(WeatherAlerts.next(forecast: [hour(0), hour(1), hour(2)], now: now, state: &state) == nil)
        #expect(WeatherAlerts.next(forecast: [], now: now, state: &state) == nil)
    }

    @Test func rainComingGivesItsStartTime() {
        var state = WeatherAlertState()
        let alert = WeatherAlerts.next(forecast: [hour(0, rain: 10), hour(1, "RAIN", rain: 80)], now: now, state: &state)
        #expect(alert?.kind == .rain)
        #expect(text(alert) == "Rain from 16:30 · 80% chance")
        #expect(state.isWet)
        // Already wet: no repeat, even an hour later.
        #expect(WeatherAlerts.next(forecast: [hour(1, "RAIN", rain: 80), hour(2, "RAIN", rain: 80)],
                                   now: now.addingTimeInterval(3_700), state: &state) == nil)
    }

    @Test func rainNowSaysNow() {
        var state = WeatherAlertState()
        #expect(text(WeatherAlerts.next(forecast: [hour(0, "HEAVY_RAIN", rain: 90)], now: now, state: &state)) == "Rain now · 90% chance")
    }

    @Test func rainFurtherThanAnHourIsIgnored() {
        var state = WeatherAlertState()
        #expect(WeatherAlerts.next(forecast: [hour(0), hour(1), hour(2, "RAIN", rain: 90)], now: now, state: &state) == nil)
    }

    @Test func stormBeatsEverything() {
        var state = WeatherAlertState()
        let forecast = [hour(0, feels: 41, gust: 55), hour(1, "THUNDERSTORM", rain: 70, thunder: 80)]
        let alert = WeatherAlerts.next(forecast: forecast, now: now, state: &state)
        #expect(alert?.kind == .storm)
        #expect(text(alert) == "Thunderstorm from 16:30 · Find shelter")
        #expect(state.isWet)
    }

    @Test func windThenHeatRespectingThe15MinuteGap() {
        var state = WeatherAlertState()
        let forecast = [hour(0, feels: 40.4, gust: 47.6), hour(1, feels: 39, gust: 30), hour(2, feels: 39, gust: 45)]
        #expect(text(WeatherAlerts.next(forecast: forecast, now: now, state: &state)) == "Strong gusts · Up to 48 km/h")
        // Heat waits for the 15-minute gap…
        #expect(WeatherAlerts.next(forecast: forecast, now: now.addingTimeInterval(10 * 60), state: &state) == nil)
        // …then comes, and wind doesn't repeat within the hour.
        #expect(text(WeatherAlerts.next(forecast: forecast, now: now.addingTimeInterval(16 * 60), state: &state))
                == "Feels like 40° · Take a water break")
        #expect(WeatherAlerts.next(forecast: forecast, now: now.addingTimeInterval(32 * 60), state: &state) == nil)
        // An hour after the first wind alert it may come again.
        #expect(WeatherAlerts.next(forecast: forecast, now: now.addingTimeInterval(61 * 60), state: &state)?.kind == .wind)
    }

    @Test func rainEasingAfterRain() {
        var state = WeatherAlertState()
        let forecast = [hour(0, "RAIN", rain: 85), hour(1, "MOSTLY_CLOUDY", rain: 20)]
        #expect(WeatherAlerts.next(forecast: forecast, now: now, state: &state)?.kind == .rain)
        let easing = WeatherAlerts.next(forecast: forecast, now: now.addingTimeInterval(16 * 60), state: &state)
        #expect(text(easing) == "Rain easing from 16:30 · Drier road ahead")
        #expect(!state.isWet)
        // Easing is only news after a rain alert.
        var fresh = WeatherAlertState()
        #expect(WeatherAlerts.next(forecast: [hour(0, rain: 10), hour(1, rain: 5)], now: now, state: &fresh) == nil)
    }

    @Test func dryAgainResetsSoNewRainIsNews() {
        var state = WeatherAlertState()
        state.isWet = true
        #expect(WeatherAlerts.next(forecast: [hour(0), hour(1)], now: now, state: &state) == nil)
        #expect(!state.isWet)
        #expect(WeatherAlerts.next(forecast: [hour(0), hour(1, "RAIN", rain: 70)], now: now.addingTimeInterval(60),
                                   state: &state)?.kind == .rain)
    }

    // MARK: Before a ride

    @Test func outlookPicksTheMostSeriousThingAhead() {
        let fine = [hour(0), hour(1), hour(2)]
        #expect(WeatherAlerts.outlook(fine, now: now) == nil)
        let rainLater = [hour(0), hour(1), hour(3, "RAIN", rain: 70)]
        #expect(text(WeatherAlerts.outlook(rainLater, now: now)) == "Rain from 18:30 · 70% chance")
        // Beyond the window it's not news yet.
        #expect(WeatherAlerts.outlook([hour(0), hour(8, "RAIN", rain: 90)], now: now) == nil)
        // A storm later beats rain sooner; rain beats heat.
        let mixed = [hour(0, feels: 39), hour(1, "RAIN", rain: 70), hour(4, "THUNDERSTORM", rain: 80, thunder: 70)]
        #expect(WeatherAlerts.outlook(mixed, now: now)?.kind == .storm)
        #expect(WeatherAlerts.outlook([hour(0, feels: 39), hour(1, "RAIN", rain: 70)], now: now)?.kind == .rain)
        #expect(text(WeatherAlerts.outlook([hour(0, feels: 40.2)], now: now)) == "Feels like 40° · Take a water break")
        // Raining already: "now".
        #expect(text(WeatherAlerts.outlook([hour(0, "RAIN", rain: 90)], now: now)) == "Rain now · 90% chance")
    }

    // MARK: Sunset

    @Test func sunsetOnceInTheLastHalfHourWithDistanceLeft() {
        var state = WeatherAlertState()
        let sunset = now.addingTimeInterval(25 * 60)
        #expect(WeatherAlerts.sunset(sunset, now: now.addingTimeInterval(-10 * 60), remainingMeters: 48_000, state: &state) == nil)
        #expect(WeatherAlerts.sunset(sunset, now: now, remainingMeters: 3_000, state: &state) == nil)
        #expect(WeatherAlerts.sunset(sunset, now: now, remainingMeters: nil, state: &state) == nil)
        let alert = WeatherAlerts.sunset(sunset, now: now, remainingMeters: 48_000, state: &state)
        #expect(text(alert) == "Sunset at 16:35 · 48 km to go")
        #expect(alert?.headline(time: { _ in "16:35" }) == "Sunset at 16:35")
        #expect(WeatherAlerts.sunset(sunset, now: now.addingTimeInterval(16 * 60), remainingMeters: 40_000, state: &state) == nil)
        var after = WeatherAlertState()
        #expect(WeatherAlerts.sunset(sunset, now: sunset.addingTimeInterval(60), remainingMeters: 40_000, state: &after) == nil)
    }

    @Test func sunsetTimesMatchAlmanac() throws {
        func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
        // New Delhi, 17 Nov 2026: sunset ≈ 17:27 IST = 11:57 UTC.
        let delhi = try #require(Sun.sunset(near: utc("2026-11-17T04:30:00Z"), at: Coordinate(latitude: 28.61, longitude: 77.21)))
        #expect(abs(delhi.timeIntervalSince(utc("2026-11-17T11:57:00Z"))) < 5 * 60)
        // San Francisco, 17 Nov 2026 (12:43 PST): sunset ≈ 16:57 PST = 00:57 UTC on the 18th.
        let sf = try #require(Sun.sunset(near: utc("2026-11-17T20:43:00Z"), at: Coordinate(latitude: 37.79, longitude: -122.41)))
        #expect(abs(sf.timeIntervalSince(utc("2026-11-18T00:57:00Z"))) < 5 * 60)
        // Polar night: no sunset.
        #expect(Sun.sunset(near: utc("2026-12-21T12:00:00Z"), at: Coordinate(latitude: 78.2, longitude: 15.6)) == nil)
    }

    // MARK: Where to look

    @Test func forecastPointLooksAheadAlongTheRoute() {
        let start = Coordinate(latitude: 12.0, longitude: 76.0)
        let route = (0...60).map { Coordinate(latitude: 12.0 + Double($0) / 111.195, longitude: 76.0) } // 1 km steps north
        // 15 m/s for 30 min = 27 km ahead.
        let point = WeatherAlerts.forecastPoint(from: start, routeAhead: route, speedMps: 15)
        #expect(abs(start.distance(to: point) - 27_000) < 100)
        // Slow or stopped: at least 5 km; never past the route's end; no route → here.
        #expect(abs(start.distance(to: WeatherAlerts.forecastPoint(from: start, routeAhead: route, speedMps: 0)) - 5_000) < 100)
        let short = Array(route.prefix(4))
        #expect(WeatherAlerts.forecastPoint(from: start, routeAhead: short, speedMps: 15) == short.last)
        #expect(WeatherAlerts.forecastPoint(from: start, routeAhead: [], speedMps: 15) == start)
    }
}
