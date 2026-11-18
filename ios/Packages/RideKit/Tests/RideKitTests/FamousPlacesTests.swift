import Foundation
import Testing
@testable import RideKit

@Suite("Famous places ahead")
struct FamousPlacesTests {
    let rider = Coordinate(latitude: 12.5000, longitude: 76.9000)

    /// ~`meters` north (positive) or south (negative) of the rider.
    func north(_ meters: Double) -> Coordinate {
        Coordinate(latitude: rider.latitude + meters / 111_195, longitude: rider.longitude)
    }

    func place(_ name: String, at c: Coordinate, rating: Double = 4.5, reviews: Int = 5_000, id: String? = nil) -> Place {
        Place(name: name, coordinate: c, primaryType: "tourist_attraction", id: id ?? name, rating: rating, ratingCount: reviews)
    }

    @Test func famousNeedsReviewsAndRating() {
        #expect(FamousPlaces.isFamous(place("Fort", at: rider)))
        #expect(!FamousPlaces.isFamous(place("Tiny park", at: rider, reviews: 40)))
        #expect(!FamousPlaces.isFamous(place("Meh", at: rider, rating: 3.6)))
        #expect(!FamousPlaces.isFamous(Place(name: "No data", coordinate: rider)))
    }

    @Test func announcesTheThreeNearestWithin2km() {
        let candidates = [
            place("D", at: north(1_900)), place("A", at: north(400)), place("C", at: north(1_500)),
            place("B", at: north(900)), place("Far", at: north(2_600)),
        ]
        let ahead = FamousPlaces.ahead(of: rider, course: 0, candidates: candidates, alreadyAnnounced: [])
        #expect(ahead.map(\.place.name) == ["A", "B", "C"])
        #expect(abs(ahead[0].distance - 400) < 5)
    }

    @Test func skipsPlacesBehindTheRider() {
        let candidates = [place("Behind", at: north(-500)), place("Ahead", at: north(800))]
        let heading = FamousPlaces.ahead(of: rider, course: 0, candidates: candidates, alreadyAnnounced: [])
        #expect(heading.map(\.place.name) == ["Ahead"])
        // Unknown course (standing still): distance only.
        let still = FamousPlaces.ahead(of: rider, course: nil, candidates: candidates, alreadyAnnounced: [])
        #expect(still.map(\.place.name) == ["Behind", "Ahead"])
        // CLLocation reports an invalid course as -1.
        #expect(FamousPlaces.ahead(of: rider, course: -1, candidates: candidates, alreadyAnnounced: []).count == 2)
    }

    @Test func skipsAnnouncedDuplicatesUnfamousAndSavedSpots() {
        let fort = place("Fort", at: north(500))
        let candidates = [fort, fort, place("Lake", at: north(700)), place("Shop", at: north(300), reviews: 10),
                          place("Temple", at: north(900))]
        let ahead = FamousPlaces.ahead(of: rider, course: 0, candidates: candidates,
                                       alreadyAnnounced: [FamousPlaces.key(for: place("Lake", at: north(700)))],
                                       savedSpots: [north(950)])
        #expect(ahead.map(\.place.name) == ["Fort"])
    }

    @Test func keyFallsBackToNameAndPosition() {
        let unnamed = Place(name: "Viewpoint", coordinate: Coordinate(latitude: 1, longitude: 2))
        #expect(FamousPlaces.key(for: unnamed) == "Viewpoint@1.000000,2.000000")
        #expect(FamousPlaces.key(for: place("X", at: rider, id: "ChIJ123")) == "ChIJ123")
    }

    @Test func searchesAgainEvery3km() {
        #expect(FamousPlaces.needsSearch(at: rider, lastSearch: nil))
        #expect(!FamousPlaces.needsSearch(at: north(2_500), lastSearch: rider))
        #expect(FamousPlaces.needsSearch(at: north(3_100), lastSearch: rider))
    }

    @Test func headingFallsBackToTheRoadRidden() throws {
        let t0 = Date(timeIntervalSince1970: 0)
        func fix(_ meters: Double, _ s: Double, speed: Double? = 8, course: Double? = nil) -> TrackPoint {
            TrackPoint(timestamp: t0.addingTimeInterval(s), coordinate: north(meters), speed: speed, course: course)
        }
        // GPS course wins while moving.
        #expect(FamousPlaces.heading(of: [fix(0, 0), fix(80, 10, course: 45)]) == 45)
        // No course (simulator, slow traffic): bearing over the last 50 m — here due north.
        let derived = try #require(FamousPlaces.heading(of: [fix(0, 0), fix(30, 4), fix(60, 8), fix(70, 9)]))
        #expect(derived < 0.5 || derived > 359.5)
        // Crawling with a course: the course is noise, use the road ridden instead (here due south).
        let south = try #require(FamousPlaces.heading(of: [fix(100, 0), fix(0, 30, speed: 1, course: 10)]))
        #expect(abs(south - 180) < 0.5)
        // Not far enough yet, or no track.
        #expect(FamousPlaces.heading(of: [fix(0, 0), fix(20, 3)]) == nil)
        #expect(FamousPlaces.heading(of: []) == nil)
    }

    @Test func bearingsAndAngles() {
        #expect(abs(FamousPlaces.bearing(from: rider, to: north(1_000))) < 0.5)
        let east = Coordinate(latitude: rider.latitude, longitude: rider.longitude + 0.01)
        #expect(abs(FamousPlaces.bearing(from: rider, to: east) - 90) < 0.5)
        #expect(abs(FamousPlaces.bearing(from: rider, to: north(-1_000)) - 180) < 0.5)
        #expect(FamousPlaces.angle(between: 350, and: 10) == 20)
        #expect(FamousPlaces.angle(between: 0, and: 180) == 180)
    }

    @Test func summaryListsNamesAndDistances() {
        let ahead = [(place: place("Fort", at: rider), distance: 1_200.0), (place: place("Lake", at: rider), distance: 1_800.0)]
        #expect(FamousPlaces.summary(ahead, distance: { String(format: "%.1f km", $0 / 1_000) }) == "Fort 1.2 km · Lake 1.8 km")
    }

    @Test func famousRequestAsksForRatingsRankedByPopularity() throws {
        let request = GooglePlaces.famousRequest(around: rider, radius: 5_000, apiKey: "K", bundleID: "b")
        let mask = try #require(request.value(forHTTPHeaderField: "X-Goog-FieldMask"))
        #expect(mask.contains("places.rating") && mask.contains("places.userRatingCount") && mask.contains("places.id"))
        let data = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["rankPreference"] as? String == "POPULARITY")
        #expect(json["maxResultCount"] as? Int == 20)
        let types = try #require(json["includedTypes"] as? [String])
        #expect(types.contains("tourist_attraction") && !types.contains("gas_station") && !types.contains("restaurant"))
        // Plain nearby search stays in the cheaper SKU.
        let plain = GooglePlaces.nearbyRequest(around: rider, radius: 150, apiKey: "K", bundleID: "b")
        #expect(plain.value(forHTTPHeaderField: "X-Goog-FieldMask")?.contains("rating") == false)
    }

    @Test func parsesRatings() throws {
        let json = """
        {"places":[{"id":"ChIJ1","displayName":{"text":"Fort"},"location":{"latitude":12.4,"longitude":76.7},
          "rating":4.6,"userRatingCount":21034,"primaryType":"historical_landmark"}]}
        """
        let places = try GooglePlaces.places(from: Data(json.utf8))
        #expect(places.first?.id == "ChIJ1")
        #expect(places.first?.rating == 4.6)
        #expect(places.first?.ratingCount == 21_034)
    }
}
