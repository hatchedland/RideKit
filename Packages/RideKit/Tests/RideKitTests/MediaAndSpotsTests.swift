import Foundation
import Testing
@testable import RideKit

@Suite("Ride album window")
struct RideMediaWindowTests {
    let start = Fixtures.start
    var end: Date { start.addingTimeInterval(3 * 3600) }

    func item(_ id: String, _ minutes: Double, _ kind: MediaCandidate.Kind = .photo) -> MediaCandidate {
        MediaCandidate(id: id, capturedAt: start.addingTimeInterval(minutes * 60), kind: kind)
    }

    @Test func includesEverythingBetweenStartAndEndInclusive() {
        let window = RideMediaWindow(start: start, end: end)
        #expect(window.contains(item("a", 0)))
        #expect(window.contains(item("b", 180)))
        #expect(window.contains(item("c", 90, .video)))
        #expect(window.contains(item("d", 90, .livePhoto)))
        #expect(!window.contains(item("e", -0.1)))
        #expect(!window.contains(item("f", 180.1)))
    }

    @Test func screenshotsExcludedByDefault() {
        #expect(!RideMediaWindow(start: start, end: end).contains(item("s", 10, .screenshot)))
        #expect(!RideMediaWindow(start: start, end: end).contains(item("r", 10, .screenRecording)))
        #expect(RideMediaWindow(start: start, end: end, includeScreenshots: true).contains(item("s", 10, .screenshot)))
    }

    @Test func itemsToAddSkipsExistingAndSortsByTime() {
        let window = RideMediaWindow(start: start, end: end)
        let candidates = [item("late", 120), item("early", 5), item("there", 50), item("outside", 500)]
        #expect(window.itemsToAdd(from: candidates, alreadyInAlbum: ["there"]) == ["early", "late"])
    }

    @Test func lateArrivalSweepLastsFortyEightHours() {
        let window = RideMediaWindow(start: start, end: end)
        #expect(window.needsLateSweep(now: end.addingTimeInterval(47 * 3600)))
        #expect(!window.needsLateSweep(now: end.addingTimeInterval(49 * 3600)))
    }

    @Test func edgeOfferFindsItemsJustOutsideTheRide() {
        let window = RideMediaWindow(start: start, end: end)
        let candidates = [item("before", -20), item("wayBefore", -45), item("during", 60), item("after", 200), item("wayAfter", 230)]
        let edge = window.edgeCandidates(from: candidates)
        #expect(edge.before.map(\.id) == ["before"])
        #expect(edge.after.map(\.id) == ["after"])
    }

    @Test func endBeforeStartIsClamped() {
        let window = RideMediaWindow(start: start, end: start.addingTimeInterval(-10))
        #expect(window.end == start)
    }
}

@Suite("Media placement")
struct MediaPlacementTests {
    let fort = SpotReference(id: UUID(), coordinate: Fixtures.indiaGate)
    let dhaba = SpotReference(id: UUID(), coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: 250))

    @Test func attachesToNearestSpotWithin150m() {
        let photo = MediaCandidate(id: "p", capturedAt: Fixtures.start, coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: 140))
        #expect(MediaPlacer.place(photo, spots: [fort, dhaba]) == .spot(dhaba.id))  // 110 m vs 140 m
    }

    @Test func pinsOnRouteWhenNoSpotNearby() {
        let c = Fixtures.east(of: Fixtures.indiaGate, meters: 400)
        let photo = MediaCandidate(id: "p", capturedAt: Fixtures.start, coordinate: c)
        #expect(MediaPlacer.place(photo, spots: [fort, dhaba]) == .route(c))
    }

    @Test func unplacedWithoutLocation() {
        let photo = MediaCandidate(id: "p", capturedAt: Fixtures.start)
        #expect(MediaPlacer.place(photo, spots: [fort]) == .unplaced)
    }

    @Test func placesBatch() {
        let items = [
            MediaCandidate(id: "a", capturedAt: Fixtures.start, coordinate: Fixtures.indiaGate),
            MediaCandidate(id: "b", capturedAt: Fixtures.start),
        ]
        #expect(MediaPlacer.place(items, spots: [fort]) == ["a": .spot(fort.id), "b": .unplaced])
    }
}

@Suite("Wishlist")
struct WishlistTests {
    // Ride north at 15 m/s for 10 min, stop 3 min, continue 10 min.
    let track = Fixtures.track(segments: [(600, 15), (180, 0), (600, 15)])
    var stopPoint: Coordinate { Fixtures.north(of: Fixtures.indiaGate, meters: 9_000) }

    @Test func stopDetectorFindsLongStopsOnly() {
        let withRedLight = Fixtures.track(segments: [(60, 10), (40, 0), (60, 10), (150, 0), (10, 10)])
        let stops = StopDetector.stops(in: withRedLight)
        #expect(stops.count == 1)
        #expect(stops.first.map { $0.duration >= 120 } == true)
    }

    @Test func stoppingNearAWishlistSpotVisitsIt() {
        let spot = SpotReference(id: UUID(), coordinate: Fixtures.east(of: stopPoint, meters: 100))
        let visits = WishlistMatcher.visits(wishlist: [spot], track: track, media: [])
        #expect(visits.count == 1)
        #expect(visits.first?.spotID == spot.id)
        #expect(visits.first?.date == Fixtures.start.addingTimeInterval(601))  // first stationary fix
    }

    @Test func ridingPastDoesNotVisit() {
        // Directly on the route, but the rider never stopped there.
        let spot = SpotReference(id: UUID(), coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: 3_000))
        #expect(WishlistMatcher.visits(wishlist: [spot], track: track, media: []).isEmpty)
    }

    @Test func photoNearSpotVisitsIt() {
        let spotCoordinate = Fixtures.north(of: Fixtures.indiaGate, meters: 3_000)
        let spot = SpotReference(id: UUID(), coordinate: spotCoordinate)
        let photo = MediaCandidate(id: "p1", capturedAt: Fixtures.start.addingTimeInterval(200),
                                   coordinate: Fixtures.east(of: spotCoordinate, meters: 60))
        let visits = WishlistMatcher.visits(wishlist: [spot], track: track, media: [photo])
        #expect(visits.first?.evidence == .photo(mediaID: "p1"))
    }

    @Test func farStopDoesNotVisit() {
        let spot = SpotReference(id: UUID(), coordinate: Fixtures.east(of: stopPoint, meters: 400))
        #expect(WishlistMatcher.visits(wishlist: [spot], track: track, media: []).isEmpty)
    }

    @Test func nearbyAlertsOnceNearestFirst() {
        let near = SpotReference(id: UUID(), coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: 800))
        let mid = SpotReference(id: UUID(), coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: 1_900))
        let far = SpotReference(id: UUID(), coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: 5_000))
        let alerts = WishlistMatcher.nearbyAlerts(position: Fixtures.indiaGate, wishlist: [far, mid, near], alreadyAlerted: [])
        #expect(alerts.map(\.spot.id) == [near.id, mid.id])
        let again = WishlistMatcher.nearbyAlerts(position: Fixtures.indiaGate, wishlist: [far, mid, near], alreadyAlerted: [near.id])
        #expect(again.map(\.spot.id) == [mid.id])
    }

    @Test func revisitDetection() {
        let existing = SpotReference(id: UUID(), coordinate: Fixtures.indiaGate)
        #expect(RevisitDetector.existingSpot(near: Fixtures.east(of: Fixtures.indiaGate, meters: 80), in: [existing]) == existing)
        #expect(RevisitDetector.existingSpot(near: Fixtures.east(of: Fixtures.indiaGate, meters: 120), in: [existing]) == nil)
    }
}

@Suite("Ride naming")
struct RideNamingTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }
    let locale = Locale(identifier: "en_IN")
    var date: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7))! }

    func resolve(_ input: String, _ existing: [String] = []) -> String {
        RideNaming.resolve(input, startedAt: date, existingNames: existing, calendar: calendar, locale: locale)
    }

    @Test func usesTypedName() {
        #expect(resolve("  Rishikesh run ") == "Rishikesh run")
    }

    @Test func emptyNameGetsDatedDefault() {
        #expect(resolve("   ") == "Ride · 12 Oct 2026")
    }

    @Test func duplicateNamesGetDateThenCounter() {
        #expect(resolve("Rishikesh run", ["rishikesh RUN"]) == "Rishikesh run · 12 Oct 2026")
        #expect(resolve("Rishikesh run", ["Rishikesh run", "Rishikesh run · 12 Oct 2026"]) == "Rishikesh run · 12 Oct 2026 (2)")
        #expect(resolve("", ["Ride · 12 Oct 2026", "Ride · 12 Oct 2026 (2)"]) == "Ride · 12 Oct 2026 (3)")
    }

    @Test func alreadyDatedNameIsNotDatedTwice() {
        #expect(resolve("Some other · 12 Oct 2026", ["Some other · 12 Oct 2026"]) == "Some other · 12 Oct 2026 (2)")
    }

    @Test func slashesAreReplaced() {
        #expect(resolve("Delhi/Agra") == "Delhi-Agra")
    }

    @Test func suggestionsFilterDedupeAndLimit() {
        let s = RideNaming.suggestions(
            for: "ri",
            recentRideNames: ["Rishikesh run", "Sunday ride", "rishikesh run"],
            wishlistSpotNames: ["Rishikesh ghats", "Chandratal", ""],
            limit: 3
        )
        #expect(s == ["Rishikesh run", "Sunday ride", "Rishikesh ghats"])
        #expect(RideNaming.suggestions(for: "", recentRideNames: ["A", "B"], wishlistSpotNames: ["C"], limit: 2) == ["A", "B"])
        #expect(RideNaming.suggestions(for: "chandratal", recentRideNames: [], wishlistSpotNames: ["Chandratal"]).isEmpty)
    }
}

@Suite("Export")
struct ExportTests {
    let spots = [
        ExportSpot(name: "Tea & \"snacks\" <stall>", notes: "Best chai", category: "food", visited: true,
                   coordinate: Coordinate(latitude: 30.1, longitude: 78.3)),
        ExportSpot(name: "Chandratal", visited: false, coordinate: Coordinate(latitude: 32.4755, longitude: 77.6166)),
    ]

    @Test func gpxContainsEscapedWaypointsAndTrack() {
        let gpx = GeoExport.gpx(name: "Run", track: Fixtures.track(segments: [(2, 10)], altitude: { _ in 210 }), spots: spots)
        #expect(gpx.contains("<name>Tea &amp; &quot;snacks&quot; &lt;stall&gt;</name>"))
        #expect(gpx.contains("<wpt lat=\"30.100000\" lon=\"78.300000\">"))
        #expect(gpx.contains("api=1&amp;query=30.100000,78.300000"))
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 3)
        #expect(gpx.contains("<ele>210.0</ele>"))
    }

    @Test func kmlSplitsVisitedAndWishlistWithLonLatOrder() throws {
        let kml = GeoExport.kml(name: "Spots", spots: spots)
        let visited = try #require(kml.range(of: "<name>Visited</name>"))
        let wishlist = try #require(kml.range(of: "<name>Want to go</name>"))
        let tea = try #require(kml.range(of: "Tea &amp;"))
        let lake = try #require(kml.range(of: "<name>Chandratal</name>"))
        #expect(visited.lowerBound < tea.lowerBound && tea.lowerBound < wishlist.lowerBound)
        #expect(wishlist.lowerBound < lake.lowerBound)
        #expect(kml.contains("<coordinates>77.616600,32.475500,0</coordinates>"))
    }
}
