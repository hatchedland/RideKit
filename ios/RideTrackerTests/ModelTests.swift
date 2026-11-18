import Foundation
import RideKit
import Testing
@testable import RideTracker

@MainActor
@Suite("App models")
struct ModelTests {
    let lake = Coordinate(latitude: 32.4755, longitude: 77.6166)

    @Test func newSpotStoresGoogleMapsLink() {
        let spot = Spot(coordinate: lake, status: .wantToGo)
        #expect(spot.googleMapsURL == "https://www.google.com/maps/search/?api=1&query=32.475500,77.616600")
        #expect(spot.visits.isEmpty)
    }

    @Test func movingASpotUpdatesItsLink() {
        let spot = Spot(coordinate: lake, status: .visited)
        spot.coordinate = Coordinate(latitude: 30, longitude: 78)
        #expect(spot.googleMapsURL.hasSuffix("query=30.000000,78.000000"))
        #expect(spot.visits.count == 1)
    }

    @Test func autoVisitCanBeUndone() {
        let spot = Spot(name: "Chandratal", coordinate: lake, status: .wantToGo)
        let rideID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        spot.markVisited(on: date, byRide: rideID)
        #expect(spot.status == .visited)
        spot.undoAutoVisit(fromRide: UUID(), on: date)      // a different ride can't undo it
        #expect(spot.status == .visited)
        spot.undoAutoVisit(fromRide: rideID, on: date)
        #expect(spot.status == .wantToGo)
        #expect(spot.visits.isEmpty)
    }

    @Test func displayNameFallsBack() {
        let spot = Spot(coordinate: lake, status: .visited)
        #expect(spot.displayName == "Spot at 32.475500,77.616600")
        spot.address = "Spiti, Himachal Pradesh"
        #expect(spot.displayName == "Spiti, Himachal Pradesh")
        spot.name = "Chandratal"
        #expect(spot.displayName == "Chandratal")
    }

    @Test func rideTrackRoundTrips() throws {
        let ride = Ride(id: UUID(), name: "Test", startedAt: .now)
        let points = (0..<10).map {
            TrackPoint(timestamp: Date(timeIntervalSince1970: Double($0)), coordinate: Coordinate(latitude: 28 + Double($0) * 0.001, longitude: 77))
        }
        ride.trackData = try TrackCodec.encode(points)
        #expect(ride.decodedTrack() == points)
    }

    @Test func formatting() {
        #expect(Format.distance(12_345, usesMetric: true) == "12.3 km")
        #expect(Format.distance(160_934.4, usesMetric: false) == "100 mi")
        #expect(Format.speed(25, usesMetric: true) == "90")
        #expect(Format.duration(3_725) == "1:02:05")
        #expect(Format.duration(65) == "1:05")
    }

    @Test func liveActivityText() {
        let state = RideActivityAttributes.ContentState(speedMps: 20, distanceMeters: 12_500, isPaused: false,
                                                        albumItemCount: 3, lastSpotName: nil, usesMetric: true)
        #expect(state.speedText == "72")
        #expect(state.distanceText == "12.5 km")
    }
}
