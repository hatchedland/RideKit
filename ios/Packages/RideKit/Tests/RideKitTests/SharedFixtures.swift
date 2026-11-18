import Foundation
import Testing
@testable import RideKit

// Golden files in `spec/fixtures`, shared with the Android port (see spec/fixtures/README.md).
// The cases below are written in Swift; `RIDEKIT_WRITE_FIXTURES=1 ./scripts/test.sh --filter SharedFixture`
// rewrites the JSON (inputs + what this RideKit returns). Every normal run checks the JSON still matches.

enum SharedFixture {
    static let dir = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../../spec/fixtures").standardized
    static var writing: Bool { ProcessInfo.processInfo.environment["RIDEKIT_WRITE_FIXTURES"] == "1" }

    struct File<Input: Codable, Output: Codable & Equatable>: Codable {
        var about: String
        var cases: [Case]
        struct Case: Codable {
            var name: String
            var input: Input
            var expected: Output
        }
    }

    static func verify<Input: Codable, Output: Codable & Equatable>(
        _ name: String, about: String, cases: () -> [(String, Input)], run: (Input) -> Output
    ) throws {
        let url = dir.appending(path: "\(name).json")
        if writing {
            // Expected values come from the inputs as decoded from JSON, exactly what Android reads.
            let roundTripped = try cases().map { ($0.0, try JSONDecoder().decode(Input.self, from: JSONEncoder().encode($0.1))) }
            let file = File<Input, Output>(about: about, cases: roundTripped.map { .init(name: $0.0, input: $0.1, expected: run($0.1)) })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try compactNumberArrays(String(decoding: encoder.encode(file), as: UTF8.self)).write(to: url, atomically: true, encoding: .utf8)
        }
        let file = try JSONDecoder().decode(File<Input, Output>.self, from: Data(contentsOf: url))
        #expect(!file.cases.isEmpty)
        for item in file.cases {
            #expect(run(item.input) == item.expected, "\(name): \(item.name)")
        }
    }

    static func verify<Input: Codable, Output: Codable & Equatable>(
        _ name: String, about: String, cases: [(String, Input)], run: (Input) -> Output
    ) throws {
        try verify(name, about: about, cases: { cases }, run: run)
    }

    /// Track points are arrays of numbers: keep each on one line so the files stay readable.
    static func compactNumberArrays(_ json: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"\[[\s0-9.eE+\-,nul]*\]"#)
        var result = json
        for match in regex.matches(in: json, range: NSRange(json.startIndex..., in: json)).reversed() {
            let range = Range(match.range, in: result)!
            let collapsed = result[range].replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "[ ", with: "[").replacingOccurrences(of: " ]", with: "]")
            result.replaceSubrange(range, with: collapsed)
        }
        return result + "\n"
    }
}

// MARK: - JSON shapes (times are Unix seconds, distances meters)

struct LatLon: Codable, Equatable {
    var lat: Double
    var lon: Double
    var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lon) }
    init(_ c: Coordinate) { lat = c.latitude; lon = c.longitude }
}

/// `[t, lat, lon, alt, speed, course, hAcc, lean]`, `null` for unknown.
struct JPoint: Codable, Equatable {
    var point: TrackPoint

    init(_ point: TrackPoint) { self.point = point }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        func optional() throws -> Double? { try c.decodeNil() ? nil : c.decode(Double.self) }
        let t = try c.decode(Double.self), lat = try c.decode(Double.self), lon = try c.decode(Double.self)
        let alt = try optional(), speed = try optional(), course = try optional()
        let hAcc = try c.decode(Double.self)
        let lean = try optional()
        point = TrackPoint(timestamp: Date(timeIntervalSince1970: t), coordinate: Coordinate(latitude: lat, longitude: lon),
                           altitude: alt, speed: speed, course: course, horizontalAccuracy: hAcc, lean: lean)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        func optional(_ v: Double?) throws { if let v { try c.encode(v) } else { try c.encodeNil() } }
        try c.encode(point.timestamp.timeIntervalSince1970)
        try c.encode(point.coordinate.latitude)
        try c.encode(point.coordinate.longitude)
        try optional(point.altitude)
        try optional(point.speed)
        try optional(point.course)
        try c.encode(point.horizontalAccuracy)
        try optional(point.lean)
    }
}

extension Array where Element == JPoint {
    var points: [TrackPoint] { map(\.point) }
}

private func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
private func uuid(_ s: String) -> UUID { UUID(uuidString: s)! }

/// Builds inputs: tracks sampled every `step` seconds, coordinates rounded to 7 decimals (~1 cm).
enum Build {
    static let bengaluru = Coordinate(latitude: 12.9716, longitude: 77.5946)

    /// Unix seconds for an ISO 8601 UTC time, e.g. "2026-11-18T03:30:00Z".
    static func t(_ iso: String) -> Double { ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 }

    static func round7(_ c: Coordinate) -> Coordinate {
        Coordinate(latitude: (c.latitude * 1e7).rounded() / 1e7, longitude: (c.longitude * 1e7).rounded() / 1e7)
    }

    static func move(_ c: Coordinate, meters: Double, bearing: Double) -> Coordinate {
        let r = bearing * .pi / 180
        return Fixtures.east(of: Fixtures.north(of: c, meters: meters * cos(r)), meters: meters * sin(r))
    }

    /// Legs of (seconds, speed m/s, bearing°). `course` is left unknown, like a phone in slow traffic.
    static func track(from origin: Coordinate = bengaluru, start: Double,
                      legs: [(seconds: Int, speed: Double, bearing: Double)], step: Int = 5) -> [JPoint] {
        var position = round7(origin), t = start
        var result = [JPoint(TrackPoint(timestamp: date(t), coordinate: position, speed: legs.first?.speed))]
        for leg in legs {
            for _ in 0..<(leg.seconds / step) {
                t += Double(step)
                position = round7(move(position, meters: leg.speed * Double(step), bearing: leg.bearing))
                result.append(JPoint(TrackPoint(timestamp: date(t), coordinate: position, speed: leg.speed)))
            }
        }
        return result
    }

    static func at(_ track: [JPoint], _ seconds: Double) -> Coordinate {
        let start = track[0].point.timestamp.timeIntervalSince1970
        return track.points.coordinate(at: date(start + seconds), maxGap: .infinity) ?? track[0].point.coordinate
    }
}

@Suite("Shared fixtures (spec/fixtures)")
struct SharedFixtureTests {

    // MARK: Share privacy

    struct PrivacyInput: Codable {
        struct Zone: Codable { var center: LatLon; var radius: Double }
        var zones: [Zone]
        var endTrim: Double
        var track: [JPoint]
        /// Points (e.g. photos) asked about with `shows`.
        var probes: [LatLon]
    }
    struct PrivacyOutput: Codable, Equatable {
        /// Indices into `track` friends may see.
        var visible: [Int]
        var shows: [Bool]
    }

    @Test func sharePrivacy() throws {
        try SharedFixture.verify("share-privacy", about: """
            SharePrivacy: what friends may see of a ride. `visible` = indices of track points kept by redact(); \
            `shows` = shows(probe, track) for each probe. Zones hide points within `radius` of `center`; \
            `endTrim` meters are cut from each end (measured along the visible track).
            """, cases: {
            let ride = Build.track(start: Build.t("2026-11-18T03:30:00Z"), legs: [(600, 9.7, 0)])  // 48.5 m apart: no point sits on a 500 m edge
            let home = Build.at(ride, 0), mid = Build.at(ride, 300)
            return [
                ("trims 500 m from each end", PrivacyInput(zones: [], endTrim: 500, track: ride,
                    probes: [LatLon(home), LatLon(Build.at(ride, 30)), LatLon(mid), LatLon(Build.at(ride, 580))])),
                ("zone hides the middle too", PrivacyInput(zones: [.init(center: LatLon(mid), radius: 300)], endTrim: 500,
                    track: ride, probes: [LatLon(mid), LatLon(Build.at(ride, 200))])),
                ("short ride shares nothing", PrivacyInput(zones: [], endTrim: 500,
                    track: Build.track(start: Build.t("2026-11-18T03:30:00Z"), legs: [(90, 10, 45)]), probes: [])),
                ("end trim off, zone at home", PrivacyInput(zones: [.init(center: LatLon(home), radius: 400)], endTrim: 0,
                    track: ride, probes: [LatLon(home), LatLon(mid)])),
            ]
        }, run: { input in
            let privacy = SharePrivacy(zones: input.zones.map { PrivacyZone(name: "z", center: $0.center.coordinate, radius: $0.radius) },
                                       endTrim: input.endTrim)
            let track = input.track.points
            let kept = privacy.redact(track)
            return PrivacyOutput(visible: kept.compactMap { p in track.firstIndex { $0.timestamp == p.timestamp } },
                                 shows: input.probes.map { privacy.shows($0.coordinate, track: track) })
        })
    }

    // MARK: Wishlist

    struct WishlistInput: Codable {
        struct Spot: Codable { var id: String; var at: LatLon }
        struct Media: Codable { var id: String; var t: Double; var at: LatLon? }
        var wishlist: [Spot]
        var track: [JPoint]
        var media: [Media]
        /// nearbyAlerts(position:wishlist:alreadyAlerted:)
        var position: LatLon
        var alreadyAlerted: [String]
        /// RevisitDetector.existingSpot(near:in: wishlist)
        var revisitProbes: [LatLon]
    }
    struct WishlistOutput: Codable, Equatable {
        struct Visit: Codable, Equatable { var spotID: String; var t: Double; var evidence: String; var mediaID: String? }
        struct Nearby: Codable, Equatable { var spotID: String; var distance: Double }
        var visits: [Visit]
        var nearby: [Nearby]
        var revisit: [String?]
    }

    @Test func wishlist() throws {
        try SharedFixture.verify("wishlist", about: """
            WishlistMatcher.visits (stopped ≥ 2 min or a photo within 150 m; riding past doesn't count; earliest \
            evidence wins; sorted by time), nearbyAlerts (≤ 2 km, not yet alerted, nearest first) and \
            RevisitDetector (existing spot within 100 m). Spot ids are uppercase UUID strings.
            """, cases: {
            // 2.4 km north at 12 m/s, a 3-minute chai stop, then 2.4 km more.
            let ride = Build.track(start: Build.t("2026-11-18T04:00:00Z"), legs: [(200, 12, 0), (180, 0.3, 0), (200, 12, 0)])
            let stopPlace = Build.move(Build.at(ride, 290), meters: 60, bearing: 90)
            let passed = Build.at(ride, 450)
            let photoSpot = Build.at(ride, 80)
            let far = Build.move(Build.bengaluru, meters: 3_000, bearing: 270)
            let a = "00000000-0000-0000-0000-00000000000A", b = "00000000-0000-0000-0000-00000000000B"
            let c = "00000000-0000-0000-0000-00000000000C", d = "00000000-0000-0000-0000-00000000000D"
            let t0 = ride[0].point.timestamp.timeIntervalSince1970
            return [
                ("stop and photo count, riding past doesn't", WishlistInput(
                    wishlist: [.init(id: a, at: LatLon(stopPlace)), .init(id: b, at: LatLon(passed)),
                               .init(id: c, at: LatLon(photoSpot)), .init(id: d, at: LatLon(far))],
                    track: ride,
                    media: [.init(id: "photo-near-c", t: t0 + 90, at: LatLon(Build.move(photoSpot, meters: 100, bearing: 180))),
                            .init(id: "photo-near-c-later", t: t0 + 95, at: LatLon(photoSpot)),
                            .init(id: "photo-at-stop", t: t0 + 330, at: LatLon(stopPlace)),
                            .init(id: "photo-no-gps", t: t0 + 460, at: nil),
                            .init(id: "photo-400m-from-d", t: t0 + 500, at: LatLon(Build.move(far, meters: 400, bearing: 0)))],
                    position: LatLon(Build.bengaluru), alreadyAlerted: [b],
                    revisitProbes: [LatLon(Build.move(stopPlace, meters: 60, bearing: 0)),
                                    LatLon(Build.move(stopPlace, meters: 130, bearing: 0))])),
                ("no wishlist", WishlistInput(wishlist: [], track: ride, media: [], position: LatLon(Build.bengaluru),
                                              alreadyAlerted: [], revisitProbes: [LatLon(Build.bengaluru)])),
            ]
        }, run: { input in
            let refs = input.wishlist.map { SpotReference(id: uuid($0.id), coordinate: $0.at.coordinate) }
            let media = input.media.map { MediaCandidate(id: $0.id, capturedAt: date($0.t), coordinate: $0.at?.coordinate) }
            let visits = WishlistMatcher.visits(wishlist: refs, track: input.track.points, media: media).map { visit in
                switch visit.evidence {
                case .stopped: WishlistOutput.Visit(spotID: visit.spotID.uuidString, t: visit.date.timeIntervalSince1970, evidence: "stopped", mediaID: nil)
                case .photo(let id): WishlistOutput.Visit(spotID: visit.spotID.uuidString, t: visit.date.timeIntervalSince1970, evidence: "photo", mediaID: id)
                }
            }
            let nearby = WishlistMatcher.nearbyAlerts(position: input.position.coordinate, wishlist: refs,
                                                      alreadyAlerted: Set(input.alreadyAlerted.map(uuid)))
                .map { WishlistOutput.Nearby(spotID: $0.spot.id.uuidString, distance: $0.distance) }
            let revisit = input.revisitProbes.map { RevisitDetector.existingSpot(near: $0.coordinate, in: refs)?.id.uuidString }
            return WishlistOutput(visits: visits, nearby: nearby, revisit: revisit)
        })
    }

    // MARK: Ride time plan

    struct TimePlanInput: Codable {
        struct Ride: Codable { var distance: Double; var moving: Double; var elapsed: Double }
        var departure: Double
        var distance: Double
        var roadSeconds: Double
        var destination: LatLon
        /// Past rides, newest first.
        var rides: [Ride]
    }
    struct TimePlanOutput: Codable, Equatable {
        var paceSpeed: Double?
        var stopShare: Double
        var rideCount: Int
        var movingSeconds: Double
        var breakSeconds: Double
        var arrival: Double
        var sunset: Double?
        var latestDeparture: Double?
        var arrivesAfterDark: Bool
        var canStillArriveInDaylight: Bool
    }

    @Test func rideTimePlan() throws {
        let mysuru = LatLon(Coordinate(latitude: 12.2958, longitude: 76.6394))
        try SharedFixture.verify("ride-time-plan", about: """
            RidePace.learn(rides) + RideTimePlan(departure, distance, roadSeconds, destination, pace), including \
            Sun.sunset at the destination. Pace: rides ≥ 20 km and ≥ 20 min moving, newest 20, needs 2; speed \
            distance-weighted, stop share = median clamped to 0.05…0.45; default 15 %. Moving time = average of \
            Google and personal, never below Google, at most 1.6× Google. No sunset over 14 h or in polar night.
            """, cases: [
            ("no history: Google time + 15 % stops", TimePlanInput(departure: Build.t("2026-11-18T03:30:00Z"), distance: 145_000,
                roadSeconds: 3 * 3600, destination: mysuru, rides: [])),
            ("one usable ride is not enough", TimePlanInput(departure: Build.t("2026-11-18T03:30:00Z"), distance: 145_000,
                roadSeconds: 3 * 3600, destination: mysuru,
                rides: [.init(distance: 80_000, moving: 7_200, elapsed: 9_000), .init(distance: 15_000, moving: 1_800, elapsed: 2_000)])),
            ("learned pace, slower than Google", TimePlanInput(departure: Build.t("2026-11-18T03:30:00Z"), distance: 145_000,
                roadSeconds: 3 * 3600, destination: mysuru,
                rides: [.init(distance: 80_000, moving: 7_200, elapsed: 9_000), .init(distance: 120_000, moving: 9_600, elapsed: 13_000),
                        .init(distance: 40_000, moving: 3_000, elapsed: 3_100), .init(distance: 30_000, moving: 1_000, elapsed: 1_200)])),
            ("very slow rider capped at 1.6× Google", TimePlanInput(departure: Build.t("2026-11-18T03:30:00Z"), distance: 145_000,
                roadSeconds: 3 * 3600, destination: mysuru,
                rides: [.init(distance: 25_000, moving: 6_000, elapsed: 20_000), .init(distance: 22_000, moving: 5_000, elapsed: 5_100)])),
            ("late start arrives after dark", TimePlanInput(departure: Build.t("2026-11-18T10:30:00Z"), distance: 145_000,
                roadSeconds: 3 * 3600, destination: mysuru, rides: [])),
            ("longer than a day's ride: no sunset", TimePlanInput(departure: Build.t("2026-11-18T01:00:00Z"), distance: 900_000,
                roadSeconds: 15 * 3600, destination: LatLon(Coordinate(latitude: 18.5204, longitude: 73.8567)), rides: [])),
            ("polar night: no sunset", TimePlanInput(departure: Build.t("2026-12-15T09:00:00Z"), distance: 30_000,
                roadSeconds: 2_400, destination: LatLon(Coordinate(latitude: 69.6492, longitude: 18.9553)), rides: [])),
        ], run: { input in
            let pace = RidePace.learn(from: input.rides.map { RidePace.Sample(distanceMeters: $0.distance, movingSeconds: $0.moving, elapsedSeconds: $0.elapsed) })
            let plan = RideTimePlan(departure: date(input.departure), distanceMeters: input.distance, roadSeconds: input.roadSeconds,
                                    destination: input.destination.coordinate, pace: pace)
            return TimePlanOutput(paceSpeed: pace.movingSpeedMps, stopShare: pace.stopShare, rideCount: pace.rideCount,
                                  movingSeconds: plan.movingSeconds, breakSeconds: plan.breakSeconds,
                                  arrival: plan.arrival.timeIntervalSince1970, sunset: plan.sunset?.timeIntervalSince1970,
                                  latestDeparture: plan.latestDeparture?.timeIntervalSince1970,
                                  arrivesAfterDark: plan.arrivesAfterDark, canStillArriveInDaylight: plan.canStillArriveInDaylight)
        })
    }

    // MARK: Weather alerts

    struct WeatherInput: Codable {
        struct Hour: Codable {
            var start: Double
            var condition: String
            var feelsLike: Double?
            var rainChance: Int
            var thunderChance: Int
            var gustKmh: Double?
        }
        /// `call` is "next" (WeatherAlerts.next) or "sunset" (WeatherAlerts.sunset), run in order on one state.
        struct Step: Codable { var call: String; var now: Double; var sunset: Double?; var remaining: Double? }
        var forecast: [Hour]
        var steps: [Step]
    }
    struct JAlert: Codable, Equatable {
        var kind: String
        var at: Double?
        var percent: Int?
        var value: Double?
        init(_ a: WeatherAlert) {
            kind = a.kind.rawValue; at = a.at?.timeIntervalSince1970; percent = a.percent; value = a.value
        }
    }
    struct WeatherOutput: Codable, Equatable {
        /// One per step, `null` when nothing is announced.
        var alerts: [JAlert?]
        /// WeatherAlerts.outlook(forecast, now: first step's time, hours: 6).
        var outlook: JAlert?
    }

    @Test func weatherAlerts() throws {
        let t = Build.t
        func hour(_ iso: String, _ condition: String = "CLEAR", rain: Int = 0, thunder: Int = 0, gust: Double? = nil, feels: Double? = nil) -> WeatherInput.Hour {
            .init(start: t(iso), condition: condition, feelsLike: feels, rainChance: rain, thunderChance: thunder, gustKmh: gust)
        }
        func next(_ iso: String) -> WeatherInput.Step { .init(call: "next", now: t(iso)) }
        let afternoon = [hour("2026-11-18T08:30:00Z"), hour("2026-11-18T09:30:00Z", "RAIN", rain: 80),
                         hour("2026-11-18T10:30:00Z", "LIGHT_RAIN", rain: 70), hour("2026-11-18T11:30:00Z", "CLOUDY", rain: 10)]
        try SharedFixture.verify("weather-alerts", about: """
            WeatherAlerts.next / .sunset run in order on one WeatherAlertState, plus .outlook. Priority storm > rain > \
            wind (gust ≥ 40) > heat (feels ≥ 38) > clearing; rain only when it starts; same kind ≤ hourly; any alert \
            ≤ every 15 min; looks 60 min ahead. Rainy = chance ≥ 60, or a wet condition (RAIN, SHOWER, THUNDER, HAIL, \
            SLEET, SNOW) with ≥ 40. Stormy = thunder ≥ 50 or THUNDER/HAIL. Sunset: once, ≤ 30 min before, ≥ 5 km left.
            """, cases: [
            ("rain starts, eases, then quiet", WeatherInput(forecast: afternoon, steps: [
                next("2026-11-18T09:00:00Z"), next("2026-11-18T09:10:00Z"), next("2026-11-18T10:00:00Z"),
                next("2026-11-18T11:00:00Z"), next("2026-11-18T12:00:00Z")])),
            ("storm beats wind, wind next", WeatherInput(forecast: [
                hour("2026-11-18T09:00:00Z", "THUNDERSTORM", rain: 70, thunder: 60, gust: 55)], steps: [
                next("2026-11-18T09:05:00Z"), next("2026-11-18T09:15:00Z"), next("2026-11-18T09:25:00Z")])),
            ("heat once an hour", WeatherInput(forecast: [
                hour("2026-11-18T07:00:00Z", feels: 39.4), hour("2026-11-18T08:00:00Z", feels: 40.2)], steps: [
                next("2026-11-18T07:10:00Z"), next("2026-11-18T07:40:00Z"), next("2026-11-18T08:15:00Z")])),
            ("wet condition counts from 40 %, cloudy doesn't", WeatherInput(forecast: [
                hour("2026-11-18T07:00:00Z", "CLOUDY", rain: 55), hour("2026-11-18T08:00:00Z", "LIGHT_RAIN", rain: 45)], steps: [
                next("2026-11-18T07:00:00Z"), next("2026-11-18T07:30:00Z")])),
            ("sunset once with 5 km to go", WeatherInput(forecast: [], steps: [
                .init(call: "sunset", now: t("2026-11-18T12:00:00Z"), sunset: t("2026-11-18T12:40:00Z"), remaining: 20_000),
                .init(call: "sunset", now: t("2026-11-18T12:15:00Z"), sunset: t("2026-11-18T12:40:00Z"), remaining: 18_000),
                .init(call: "sunset", now: t("2026-11-18T12:30:00Z"), sunset: t("2026-11-18T12:40:00Z"), remaining: 15_000)])),
            ("no sunset alert when nearly there", WeatherInput(forecast: [], steps: [
                .init(call: "sunset", now: t("2026-11-18T12:20:00Z"), sunset: t("2026-11-18T12:40:00Z"), remaining: 3_000)])),
        ], run: { input in
            let forecast = input.forecast.map {
                WeatherHour(start: date($0.start), condition: $0.condition, feelsLike: $0.feelsLike,
                            rainChance: $0.rainChance, thunderChance: $0.thunderChance, gustKmh: $0.gustKmh)
            }
            var state = WeatherAlertState()
            let alerts: [JAlert?] = input.steps.map { step in
                let alert = step.call == "sunset"
                    ? WeatherAlerts.sunset(step.sunset.map(date), now: date(step.now), remainingMeters: step.remaining, state: &state)
                    : WeatherAlerts.next(forecast: forecast, now: date(step.now), state: &state)
                return alert.map(JAlert.init)
            }
            let outlook = input.steps.first.flatMap { WeatherAlerts.outlook(forecast, now: date($0.now)) }.map(JAlert.init)
            return WeatherOutput(alerts: alerts, outlook: outlook)
        })
    }

    // MARK: Famous places

    struct FamousInput: Codable {
        struct Place: Codable { var id: String?; var name: String; var at: LatLon; var rating: Double?; var ratingCount: Int? }
        var position: LatLon
        var course: Double?
        var candidates: [Place]
        var alreadyAnnounced: [String]
        var savedSpots: [LatLon]
        /// FamousPlaces.heading(of:) over this track.
        var recentTrack: [JPoint]
        /// FamousPlaces.needsSearch(at: position, lastSearch:)
        var lastSearch: LatLon?
    }
    struct FamousOutput: Codable, Equatable {
        struct Ahead: Codable, Equatable { var key: String; var distance: Double }
        var ahead: [Ahead]
        var heading: Double?
        var needsSearch: Bool
    }

    @Test func famousPlaces() throws {
        let here = Build.bengaluru
        func place(_ id: String?, _ name: String, _ meters: Double, _ bearing: Double, rating: Double? = 4.5, count: Int? = 2_000) -> FamousInput.Place {
            .init(id: id, name: name, at: LatLon(Build.round7(Build.move(here, meters: meters, bearing: bearing))), rating: rating, ratingCount: count)
        }
        let saved = Build.move(here, meters: 1_200, bearing: 10)
        try SharedFixture.verify("famous-places", about: """
            FamousPlaces.ahead: ≥ 500 reviews and ≥ 4.0, ≤ 2 km, not already announced (key = id, else \
            "name@lat,lon"), not within 150 m of a saved spot, not more than 90° off the course (unless within \
            150 m or the course is unknown), nearest 3. Also heading(of:) (GPS course when ≥ 3 m/s, else bearing \
            over the last 50 m) and needsSearch (first search, or ≥ 3 km since the last).
            """, cases: [
            ("filters and keeps the nearest three", FamousInput(
                position: LatLon(here), course: 0,
                candidates: [
                    place("north-1k", "Fort", 1_000, 0), place("south-1k", "Behind", 1_000, 180),
                    place("close-behind", "Gate", 100, 180), place("low-rating", "Meh", 500, 0, rating: 3.9, count: 900),
                    place("few-reviews", "New", 500, 0, count: 499), place("too-far", "Far", 2_500, 0),
                    place("announced", "Old news", 700, 0), place("saved", "Mine", 1_200, 10),
                    place("north-1k", "Fort again", 1_000, 0), place(nil, "Lake", 1_500, 45), place("north-1800", "Temple", 1_800, 350),
                ],
                alreadyAnnounced: ["announced"], savedSpots: [LatLon(Build.round7(saved))],
                recentTrack: Build.track(from: Build.move(here, meters: -300, bearing: 0), start: Build.t("2026-11-18T05:00:00Z"), legs: [(30, 10, 0)]),
                lastSearch: LatLon(Build.move(here, meters: 2_900, bearing: 180)))),
            ("unknown course: nothing is behind", FamousInput(
                position: LatLon(here), course: nil,
                candidates: [place("south-1k", "Behind", 1_000, 180), place(nil, "Lake", 1_500, 45)],
                alreadyAnnounced: [], savedSpots: [],
                recentTrack: Build.track(start: Build.t("2026-11-18T05:00:00Z"), legs: [(60, 0, 0)]),
                lastSearch: nil)),
            ("moved 3 km: search again", FamousInput(
                position: LatLon(here), course: 90, candidates: [], alreadyAnnounced: [], savedSpots: [],
                recentTrack: [JPoint(TrackPoint(timestamp: date(Build.t("2026-11-18T05:00:00Z")), coordinate: here, speed: 8, course: 87.5))],
                lastSearch: LatLon(Build.move(here, meters: 3_100, bearing: 270)))),
        ], run: { input in
            let candidates = input.candidates.map {
                Place(name: $0.name, coordinate: $0.at.coordinate, id: $0.id, rating: $0.rating, ratingCount: $0.ratingCount)
            }
            let ahead = FamousPlaces.ahead(of: input.position.coordinate, course: input.course, candidates: candidates,
                                           alreadyAnnounced: Set(input.alreadyAnnounced), savedSpots: input.savedSpots.map(\.coordinate))
            return FamousOutput(ahead: ahead.map { .init(key: FamousPlaces.key(for: $0.place), distance: $0.distance) },
                                heading: FamousPlaces.heading(of: input.recentTrack.points),
                                needsSearch: FamousPlaces.needsSearch(at: input.position.coordinate, lastSearch: input.lastSearch?.coordinate))
        })
    }

    // MARK: Trail

    struct TrailInput: Codable {
        struct Media: Codable { var id: String; var t: Double; var at: LatLon?; var spotID: String? }
        struct Spot: Codable { var id: String; var at: LatLon; var markedAt: Double }
        struct Song: Codable { var id: String; var t: Double }
        var rideStart: Double
        var rideEnd: Double
        var track: [JPoint]
        var media: [Media]
        var spots: [Spot]
        var songs: [Song]
    }
    struct TrailOutput: Codable, Equatable {
        struct Stop: Codable, Equatable {
            var id: String
            /// "spot" or "cluster"
            var kind: String
            var at: LatLon
            var arrivedAt: Double
            var departedAt: Double
            var distanceFromStart: Double?
            var mediaIDs: [String]
            var songIDs: [String]
        }
        struct Leg: Codable, Equatable {
            var start: Double
            var end: Double
            var distance: Double?
            var mediaIDs: [String]
            var songIDs: [String]
        }
        var stops: [Stop]
        var legs: [Leg]
    }

    @Test func trail() throws {
        let spot = "00000000-0000-0000-0000-0000000000AA"
        try SharedFixture.verify("trail", about: """
            Trail.build: stops = spots (marked or with photos) + clusters of located photos (≤ 150 m from the \
            cluster's first photo and ≤ 10 min after its last), sorted by arrival then id; photos without GPS join the \
            stop nearest in time if ≤ 10 min away, else the leg they were taken on. legs.count == stops.count + 1; \
            songs that start during a stop (arrival…departure, inclusive) go to that stop, others to the leg they started on. Distances are along the track (null without one).
            """, cases: {
            let start = Build.t("2026-11-18T04:00:00Z")
            let ride = Build.track(start: start, legs: [(900, 10, 0), (300, 0.5, 0), (600, 12, 30), (900, 12, 60)])
            let markedAt = start + 600
            return [
                ("spot, two clusters, photos without GPS, songs", TrailInput(
                    rideStart: start, rideEnd: start + 2_700, track: ride,
                    media: [
                        .init(id: "no-gps-joins-spot", t: start + 100, at: nil, spotID: nil),
                        .init(id: "on-the-road", t: start + 2_500, at: nil, spotID: nil),
                        .init(id: "at-spot", t: start + 650, at: LatLon(Build.at(ride, 600)), spotID: spot),
                        .init(id: "cluster1-a", t: start + 950, at: LatLon(Build.at(ride, 950)), spotID: nil),
                        .init(id: "cluster1-b", t: start + 1_010, at: LatLon(Build.move(Build.at(ride, 950), meters: 50, bearing: 90)), spotID: nil),
                        .init(id: "joins-cluster1", t: start + 1_150, at: nil, spotID: nil),
                        .init(id: "cluster2", t: start + 1_700, at: LatLon(Build.at(ride, 1_700)), spotID: nil),
                    ],
                    spots: [.init(id: spot, at: LatLon(Build.at(ride, 600)), markedAt: markedAt)],
                    songs: [.init(id: "song-1", t: start + 50), .init(id: "song-2", t: start + 1_000), .init(id: "song-3", t: start + 1_750)])),
                ("no track: no distances", TrailInput(
                    rideStart: start, rideEnd: start + 3_600, track: [],
                    media: [.init(id: "p1", t: start + 600, at: LatLon(Build.bengaluru), spotID: nil),
                            .init(id: "p2", t: start + 1_000, at: LatLon(Build.move(Build.bengaluru, meters: 200, bearing: 0)), spotID: nil)],
                    spots: [], songs: [])),
                ("nothing taken: one leg", TrailInput(rideStart: start, rideEnd: start + 2_700, track: ride, media: [], spots: [], songs: [])),
            ]
        }, run: { input in
            let trail = Trail.build(
                rideStart: date(input.rideStart), rideEnd: date(input.rideEnd), track: input.track.points,
                media: input.media.map { Trail.Media(id: $0.id, capturedAt: date($0.t), coordinate: $0.at?.coordinate, spotID: $0.spotID.map(uuid)) },
                spots: input.spots.map { Trail.Spot(id: uuid($0.id), coordinate: $0.at.coordinate, markedAt: date($0.markedAt)) },
                songs: input.songs.map { (id: $0.id, startedAt: date($0.t)) })
            return TrailOutput(
                stops: trail.stops.map { stop in
                    let kind: String = if case .spot = stop.kind { "spot" } else { "cluster" }
                    return .init(id: stop.id, kind: kind, at: LatLon(stop.coordinate), arrivedAt: stop.arrivedAt.timeIntervalSince1970,
                                 departedAt: stop.departedAt.timeIntervalSince1970, distanceFromStart: stop.distanceFromStart, mediaIDs: stop.mediaIDs,
                                 songIDs: stop.songIDs)
                },
                legs: trail.legs.map { .init(start: $0.start.timeIntervalSince1970, end: $0.end.timeIntervalSince1970,
                                              distance: $0.distance, mediaIDs: $0.mediaIDs, songIDs: $0.songIDs) })
        })
    }

    // MARK: Ride naming

    struct NamingInput: Codable {
        /// "resolve" (RideNaming.resolve) or "suggest" (RideNaming.suggestions).
        var call: String
        var input: String
        var startedAt: Double?
        var existingNames: [String]?
        var recentRideNames: [String]?
        var wishlistSpotNames: [String]?
        var timeZone: String
        var locale: String
    }
    struct NamingOutput: Codable, Equatable {
        var name: String?
        var suggestions: [String]?
    }

    @Test func rideNaming() throws {
        let morning = Build.t("2026-11-18T03:30:00Z")
        func resolve(_ input: String, _ existing: [String] = [], at: Double = morning) -> NamingInput {
            .init(call: "resolve", input: input, startedAt: at, existingNames: existing, timeZone: "Asia/Kolkata", locale: "en_IN")
        }
        func suggest(_ input: String, recent: [String], wishlist: [String]) -> NamingInput {
            .init(call: "suggest", input: input, recentRideNames: recent, wishlistSpotNames: wishlist, timeZone: "Asia/Kolkata", locale: "en_IN")
        }
        try SharedFixture.verify("ride-naming", about: """
            RideNaming.resolve and .suggestions. Dates use the rider's time zone and the locale's day-month-year \
            abbreviated form (ICU skeleton "dMMMy"; en_IN → "18 Nov 2026"). Names compare case-insensitively; \
            "/" becomes "-". Suggestions: recent rides then wishlist names, containing the query, no duplicates, \
            not the exact query, at most 6.
            """, cases: [
            ("empty name gets the date", resolve("  ")),
            ("typed name kept", resolve("Nandi Hills")),
            ("taken name gets the date", resolve("Nandi Hills", ["nandi hills"])),
            ("taken twice gets a counter", resolve("Nandi Hills", ["Nandi Hills", "Nandi Hills · 18 Nov 2026", "Nandi Hills · 18 Nov 2026 (2)"])),
            ("empty and taken gets a counter", resolve("", ["Ride · 18 Nov 2026"])),
            ("already dated isn't dated twice", resolve("Ride to Mysuru · 18 Nov 2026", ["Ride to Mysuru · 18 Nov 2026"])),
            ("slash becomes a dash", resolve("Day 1/3")),
            ("rider's time zone decides the day", resolve("", at: Build.t("2026-11-18T20:00:00Z"))),
            ("suggestions filter and dedupe", suggest("hill", recent: ["Nandi Hills", "Skandagiri", "Hill top", ""],
                                                       wishlist: ["nandi hills", "Kudremukh hill", "Hill"])),
            ("suggestions skip the exact query and stop at 6", suggest("", recent: ["A", "B", "C", "D"], wishlist: ["E", "F", "G"])),
            ("exact query left out", suggest("Skandagiri", recent: ["Skandagiri", "Skandagiri sunrise"], wishlist: [])),
        ], run: { input in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: input.timeZone)!
            let locale = Locale(identifier: input.locale)
            if input.call == "suggest" {
                return NamingOutput(suggestions: RideNaming.suggestions(for: input.input, recentRideNames: input.recentRideNames ?? [],
                                                                        wishlistSpotNames: input.wishlistSpotNames ?? []))
            }
            return NamingOutput(name: RideNaming.resolve(input.input, startedAt: date(input.startedAt ?? 0),
                                                         existingNames: input.existingNames ?? [], calendar: calendar, locale: locale))
        })
    }
    // MARK: App version

    struct VersionInput: Codable { var current: String; var minimum: String? }

    @Test func appVersion() throws {
        try SharedFixture.verify("app-version", about: """
            AppVersion.needsUpdate(current, minimum): compare numeric parts left to right, missing parts are 0, \
            anything after the numbers is ignored ("1.3.0-beta" == "1.3.0"). A missing or unreadable minimum \
            never blocks. `expected` is true when the app must ask the rider to update.
            """, cases: [
            ("older", VersionInput(current: "1.1.0", minimum: "1.2.0")),
            ("same", VersionInput(current: "1.2.0", minimum: "1.2.0")),
            ("two-digit part", VersionInput(current: "1.10.0", minimum: "1.9.5")),
            ("short form equals long form", VersionInput(current: "1.2", minimum: "1.2.0")),
            ("suffix ignored", VersionInput(current: "1.3.0-beta", minimum: "1.3.0")),
            ("build number ignored", VersionInput(current: "2.0 (45)", minimum: "2.0.1")),
            ("no minimum", VersionInput(current: "1.0.0", minimum: nil)),
            ("unreadable minimum never blocks", VersionInput(current: "1.0.0", minimum: "latest")),
        ], run: { AppVersion.needsUpdate(current: $0.current, minimum: $0.minimum) })
    }
    // MARK: Shared ride redaction

    struct RedactionInput: Codable {
        struct Stop: Codable { var id: String; var at: LatLon; var photoIDs: [String] }
        struct Photo: Codable { var id: String; var at: LatLon? }
        var zones: [PrivacyInput.Zone]
        var endTrim: Double
        var track: [JPoint]
        var stops: [Stop]
        var photos: [Photo]
    }
    struct RedactionOutput: Codable, Equatable {
        struct Photo: Codable, Equatable { var id: String; var at: LatLon? }
        /// Ids of the stops friends may see, in order.
        var stops: [String]
        var photos: [Photo]
    }

    @Test func sharedRideRedaction() throws {
        try SharedFixture.verify("shared-ride-redaction", about: """
            SharedRide.redacted(by: privacy, track:): stops that SharePrivacy.shows() rejects are dropped with \
            every photo taken at them; other photos lose their location if it isn't shown. Order is kept. Runs \
            on the server (supabase/functions/_shared/privacy.ts) since 2026-11-18.
            """, cases: {
            let ride = Build.track(start: Build.t("2026-11-18T03:30:00Z"), legs: [(600, 9.7, 0)])
            let home = Build.at(ride, 0), mid = Build.at(ride, 300), end = Build.at(ride, 600)
            let cafe = Build.at(ride, 200), office = Build.move(mid, meters: 40, bearing: 90)
            let stops: [RedactionInput.Stop] = [
                .init(id: "at-home", at: LatLon(home), photoIDs: ["p-home"]),
                .init(id: "cafe", at: LatLon(cafe), photoIDs: ["p-cafe", "p-cafe-2"]),
                .init(id: "office", at: LatLon(office), photoIDs: ["p-office"]),
                .init(id: "at-end", at: LatLon(end), photoIDs: []),
            ]
            let photos: [RedactionInput.Photo] = [
                .init(id: "p-home", at: LatLon(home)), .init(id: "p-cafe", at: LatLon(cafe)),
                .init(id: "p-cafe-2", at: nil), .init(id: "p-office", at: LatLon(office)),
                .init(id: "p-road-near-end", at: LatLon(Build.at(ride, 590))), .init(id: "p-road", at: LatLon(Build.at(ride, 400))),
            ]
            return [
                ("ends and a zone", RedactionInput(zones: [.init(center: LatLon(mid), radius: 300)], endTrim: 500,
                                                   track: ride, stops: stops, photos: photos)),
                ("everything off", RedactionInput(zones: [], endTrim: 0, track: ride, stops: stops, photos: photos)),
            ]
        }, run: { input in
            let privacy = SharePrivacy(zones: input.zones.map { PrivacyZone(name: "z", center: $0.center.coordinate, radius: $0.radius) },
                                       endTrim: input.endTrim)
            let t0 = input.track.first?.point.timestamp ?? .now
            let ride = SharedRide(
                id: UUID(), name: "r", startedAt: t0, endedAt: t0,
                stops: input.stops.map { SharedRide.Stop(id: $0.id, name: "", category: "", coordinate: $0.at.coordinate, arrivedAt: t0, photoIDs: $0.photoIDs) },
                photos: input.photos.map { SharedRide.Photo(id: $0.id, capturedAt: t0, coordinate: $0.at?.coordinate) })
            let redacted = ride.redacted(by: privacy, track: input.track.points)
            return RedactionOutput(stops: redacted.stops.map(\.id),
                                   photos: redacted.photos.map { .init(id: $0.id, at: $0.coordinate.map(LatLon.init)) })
        })
    }
}
