import Foundation
import Testing
@testable import RideKit

@Suite("Ride route")
struct RideRouteTests {
    let origin = Fixtures.indiaGate

    /// 1 km north, then 1 km east: an L-shaped 2 km route.
    var lRoute: RideRoute {
        let corner = Fixtures.north(of: origin, meters: 1_000)
        let end = Fixtures.east(of: corner, meters: 1_000)
        return RideRoute(coordinates: [origin, corner, end], distanceMeters: 2_000, durationSeconds: 240)
    }

    @Test func googlesSamplePolylineDecodes() {
        // From Google's documentation.
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(points.count == 3)
        #expect(points[0] == Coordinate(latitude: 38.5, longitude: -120.2))
        #expect(points[1] == Coordinate(latitude: 40.7, longitude: -120.95))
        #expect(points[2] == Coordinate(latitude: 43.252, longitude: -126.453))
    }

    @Test func encodeAndDecodeRoundTrip() {
        let points = [Coordinate(latitude: 11.4102, longitude: 76.695), Coordinate(latitude: 11.5015, longitude: 76.4934),
                      Coordinate(latitude: -33.86882, longitude: 151.20929)]
        #expect(Polyline.decode(Polyline.encode(points)) == points)
        #expect(Polyline.decode("").isEmpty)
        #expect(Polyline.decode("_p~iF").isEmpty) // a latitude without its longitude
    }

    @Test func requestIsTwoWheelerAndKeyRestricted() throws {
        let request = GoogleRoutes.request(from: origin, to: Fixtures.north(of: origin, meters: 5_000), apiKey: "K", bundleID: "b")
        #expect(request.url == GoogleRoutes.url)
        #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "b")
        #expect(request.value(forHTTPHeaderField: "X-Goog-FieldMask")?.contains("encodedPolyline") == true)
        let data = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["travelMode"] as? String == "TWO_WHEELER")
        #expect(json["units"] as? String == "METRIC")
    }

    @Test func driveIsTheFallbackMode() throws {
        #expect(GoogleRoutes.TravelMode.allCases == [.twoWheeler, .drive])
        let request = GoogleRoutes.request(from: origin, to: Fixtures.north(of: origin, meters: 5_000), mode: .drive,
                                           apiKey: "K", bundleID: "b")
        let data = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["travelMode"] as? String == "DRIVE")
    }

    @Test func parsesGooglesAnswer() throws {
        let encoded = Polyline.encode([origin, Fixtures.north(of: origin, meters: 1_000)])
        let json = #"{"routes":[{"distanceMeters":48758,"duration":"5418s","polyline":{"encodedPolyline":"\#(encoded)"}}]}"#
        let route = try #require(try GoogleRoutes.route(from: Data(json.utf8)))
        #expect(route.distanceMeters == 48_758)
        #expect(route.durationSeconds == 5_418)
        #expect(route.coordinates.count == 2)
        #expect(try GoogleRoutes.route(from: Data("{}".utf8)) == nil)
    }

    @Test func remainingDistanceFollowsTheRoadNotTheCrow() throws {
        // Half-way up the first leg: 500 m + 1 km left by road, though the end is ~1.1 km away straight.
        let position = Fixtures.north(of: origin, meters: 500)
        let progress = try #require(lRoute.progress(at: position))
        #expect(abs(progress.remainingMeters - 1_500) < 5)
        #expect(progress.offsetMeters < 1)
        #expect(!progress.isOffRoute)
        #expect(abs(lRoute.remainingSeconds(for: progress) - 180) < 1)
        #expect(lRoute.ahead(of: progress).count == 3)
    }

    @Test func offRouteWhenFarFromTheLine() throws {
        let detour = Fixtures.east(of: Fixtures.north(of: origin, meters: 300), meters: 400)
        let progress = try #require(lRoute.progress(at: detour))
        #expect(progress.isOffRoute)
        #expect(abs(progress.offsetMeters - 400) < 5)
    }

    @Test func hintKeepsTheRiderOnTheLegTheyAreOn() throws {
        // A hairpin: up 1 km and straight back down. Near the bottom, without a hint the first leg wins.
        let top = Fixtures.north(of: origin, meters: 1_000)
        let back = Fixtures.east(of: origin, meters: 10)
        let hairpin = RideRoute(coordinates: [origin, top, back], distanceMeters: 2_000, durationSeconds: 300)
        let nearBottom = Fixtures.north(of: origin, meters: 50)
        #expect(try #require(hairpin.progress(at: nearBottom)).segment == 0)
        #expect(try #require(hairpin.progress(at: nearBottom, after: 1)).segment == 1)
    }

    @Test func degenerateRoutes() {
        #expect(RideRoute(coordinates: [origin], distanceMeters: 0, durationSeconds: 0).progress(at: origin) == nil)
        #expect(RideRoute(coordinates: [], distanceMeters: 0, durationSeconds: 0).cumulative.isEmpty)
    }
}
