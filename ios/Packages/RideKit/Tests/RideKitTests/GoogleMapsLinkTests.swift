import Foundation
import Testing
@testable import RideKit

@Suite("Google Maps links")
struct GoogleMapsLinkTests {

    @Test func buildsOfficialSearchURL() {
        let url = GoogleMapsLink.url(for: Coordinate(latitude: 28.6139, longitude: 77.209))
        #expect(url.absoluteString == "https://www.google.com/maps/search/?api=1&query=28.613900,77.209000")
    }

    @Test func buildsAppURL() {
        let url = GoogleMapsLink.appURL(for: Coordinate(latitude: 32.2396, longitude: 77.1887))
        #expect(url.scheme == "comgooglemaps")
        #expect(url.absoluteString.contains("q=32.239600,77.188700"))
    }

    @Test func buildsDirectionsWithWaypoints() throws {
        let stops = (0..<3).map { Coordinate(latitude: 30 + Double($0), longitude: 78) }
        let url = try #require(GoogleMapsLink.directionsURL(through: stops))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "destination" }?.value == "32.000000,78.000000")
        #expect(items.first { $0.name == "waypoints" }?.value == "30.000000,78.000000|31.000000,78.000000")
        #expect(GoogleMapsLink.directionsURL(through: []) == nil)
    }

    @Test func directionsCapWaypointsAtNine() throws {
        let stops = (0..<15).map { Coordinate(latitude: 20 + Double($0) * 0.1, longitude: 78) }
        let url = try #require(GoogleMapsLink.directionsURL(through: stops))
        let waypoints = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "waypoints" }?.value ?? ""
        #expect(waypoints.split(separator: "|").count == 9)
    }

    @Test func roundTripsItsOwnURL() {
        let c = Coordinate(latitude: -33.856784, longitude: 151.215297)
        #expect(GoogleMapsLink.parse(GoogleMapsLink.url(for: c).absoluteString) == .coordinate(c))
    }

    @Test(arguments: [
        ("https://www.google.com/maps/search/?api=1&query=28.6129,77.2295", 28.6129, 77.2295),
        ("https://www.google.com/maps/@28.6129,77.2295,15z", 28.6129, 77.2295),
        ("https://maps.google.com/?q=28.6129,77.2295", 28.6129, 77.2295),
        ("https://maps.google.com/maps?ll=28.6129,77.2295&z=14", 28.6129, 77.2295),
        ("https://www.google.co.in/maps/place/28.6129,77.2295", 28.6129, 77.2295),
        ("https://www.google.com/maps/search/28.6129,+77.2295", 28.6129, 77.2295),
        ("https://www.google.com/maps/dir/?api=1&destination=28.6129,77.2295", 28.6129, 77.2295),
        ("28.6129, 77.2295", 28.6129, 77.2295),
        ("  -12.5,-45.25 ", -12.5, -45.25),
    ])
    func parsesCommonShapes(input: String, lat: Double, lon: Double) {
        #expect(GoogleMapsLink.parse(input) == .coordinate(Coordinate(latitude: lat, longitude: lon)))
    }

    @Test func prefersPlaceLocationOverViewportCentre() {
        // Viewport centred at @28.60,77.20 but the place itself is at !3d28.6129!4d77.2295.
        let url = "https://www.google.com/maps/place/India+Gate/@28.60,77.20,15z/data=!4m6!3m5!1s0x0:0x0!8m2!3d28.6129!4d77.2295!16s"
        #expect(GoogleMapsLink.parse(url) == .coordinate(Coordinate(latitude: 28.6129, longitude: 77.2295)))
    }

    @Test func findsURLInsideSharedText() {
        let shared = "Chandratal Lake\nhttps://www.google.com/maps/search/?api=1&query=32.4755,77.6166"
        #expect(GoogleMapsLink.parse(shared) == .coordinate(Coordinate(latitude: 32.4755, longitude: 77.6166)))
    }

    @Test(arguments: ["https://maps.app.goo.gl/AbCdEf123", "https://goo.gl/maps/xyz"])
    func shortLinksNeedResolution(link: String) {
        #expect(GoogleMapsLink.parse(link) == .needsResolution(URL(string: link)!))
    }

    @Test(arguments: [
        "",
        "hello world",
        "https://example.com/maps/@28.6,77.2,15z",
        "https://www.google.com/search?q=28.6,77.2",
        "https://www.google.com/maps/search/India+Gate",
        "95.0, 77.0",
        "28.6, 190.0",
    ])
    func rejectsNonCoordinateInput(input: String) {
        #expect(GoogleMapsLink.parse(input) == .unrecognized)
    }

    @Test func resolverFollowsShortLinks() async throws {
        let resolver = ShortLinkResolver { _ in
            URL(string: "https://www.google.com/maps/place/X/@1,2,3z/data=!3d32.4755!4d77.6166")!
        }
        let c = try await resolver.coordinate(from: "https://maps.app.goo.gl/AbC")
        #expect(c == Coordinate(latitude: 32.4755, longitude: 77.6166))
    }

    @Test func resolverReportsShortLinksWithoutCoordinates() async {
        let final = URL(string: "https://www.google.com/maps/search/some+cafe")!
        let resolver = ShortLinkResolver { _ in final }
        await #expect(throws: ShortLinkResolver.ResolveError.noCoordinates(finalURL: final)) {
            try await resolver.coordinate(from: "https://maps.app.goo.gl/AbC")
        }
    }

    @Test func resolverDoesNotFetchFullLinks() async throws {
        let resolver = ShortLinkResolver { _ in Issue.record("should not fetch"); return URL(string: "x:")! }
        #expect(try await resolver.coordinate(from: "28.1,77.1") == Coordinate(latitude: 28.1, longitude: 77.1))
        #expect(try await resolver.coordinate(from: "not a link") == nil)
    }
}
