import Foundation
import Testing
@testable import RideKit

@Suite("Ride destination")
struct DestinationTests {
    let origin = Fixtures.indiaGate

    @Test func remainingDistanceIsStraightLine() {
        let destination = RideDestination(name: "Murthal", coordinate: Fixtures.north(of: origin, meters: 42_000))
        #expect(abs(destination.remainingDistance(from: origin) - 42_000) < 1)
    }

    @Test func reachedWithinSpotRadiusOnly() {
        let target = Fixtures.north(of: origin, meters: 1_000)
        let destination = RideDestination(name: "Dhaba", coordinate: target)
        #expect(destination.isReached(at: Fixtures.north(of: target, meters: 149)))
        #expect(!destination.isReached(at: Fixtures.north(of: target, meters: 151)))
    }

    @Test func reachedAtIsFirstFixInsideRadius() {
        // 100 s at 10 m/s north: the fix at t = 86 s is the first within 150 m of 1 km north.
        let track = Fixtures.track(segments: [(seconds: 100, speed: 10)])
        let destination = RideDestination(name: "Dhaba", coordinate: Fixtures.north(of: origin, meters: 1_000))
        #expect(destination.reachedAt(track: track) == Fixtures.start.addingTimeInterval(86))
    }

    @Test func notReachedWhenRiderTurnsBack() {
        let track = Fixtures.track(segments: [(seconds: 50, speed: 10)])
        let destination = RideDestination(name: "Far away", coordinate: Fixtures.north(of: origin, meters: 5_000))
        #expect(destination.reachedAt(track: track) == nil)
        #expect(destination.reachedAt(track: []) == nil)
    }

    @Test func destinationRoundTripsThroughCodable() throws {
        let destination = RideDestination(name: "Zostel Ooty", coordinate: origin, spotID: UUID())
        let data = try JSONEncoder().encode(destination)
        #expect(try JSONDecoder().decode(RideDestination.self, from: data) == destination)
    }

    @Test func activeRideFromOlderVersionsDecodesWithoutDestination() throws {
        // Crash buffers written before destinations existed have no "destination" key.
        let json = #"{"id":"\#(UUID().uuidString)","name":"Ride","startedAt":0,"spotIDs":[]}"#
        let ride = try JSONDecoder().decode(ActiveRide.self, from: Data(json.utf8))
        #expect(ride.destination == nil)
    }

    @Test func nameGoingToDestination() {
        #expect(RideNaming.name(goingTo: RideDestination(name: " Zostel Ooty ", coordinate: origin)) == "Ride to Zostel Ooty")
        #expect(RideNaming.name(goingTo: RideDestination(name: "  ", coordinate: origin)) == "")
    }
}

@Suite("Where to? suggestions")
struct DestinationSuggestionTests {
    let here = Fixtures.indiaGate
    var near: RideDestination { RideDestination(name: "Near dhaba", coordinate: Fixtures.north(of: here, meters: 2_000), spotID: UUID()) }
    var far: RideDestination { RideDestination(name: "Far lake", coordinate: Fixtures.north(of: here, meters: 90_000), spotID: UUID()) }

    @Test func wishlistNearestFirstWhenLocationKnown() {
        let near = near, far = far
        let result = DestinationSuggestions.suggestions(query: "", wishlist: [far, near], recent: [], from: here)
        #expect(result.map(\.destination) == [near, far])
        #expect(result.allSatisfy { $0.source == .wishlist })
        #expect(abs((result.first?.distance ?? 0) - 2_000) < 1)
    }

    @Test func wishlistKeepsGivenOrderWithoutLocation() {
        let near = near, far = far
        let result = DestinationSuggestions.suggestions(query: "", wishlist: [far, near], recent: [], from: nil)
        #expect(result.map(\.destination) == [far, near])
        #expect(result.allSatisfy { $0.distance == nil })
    }

    @Test func recentsSkipWhatTheWishlistAlreadyShows() {
        let near = near
        let sameSpot = RideDestination(name: "Renamed", coordinate: Fixtures.north(of: here, meters: 50_000), spotID: near.spotID)
        let sameName = RideDestination(name: "NEAR DHABA", coordinate: Fixtures.north(of: here, meters: 60_000))
        let samePlace = RideDestination(name: "Other name", coordinate: Fixtures.north(of: near.coordinate, meters: 100))
        let fresh = RideDestination(name: "Zostel Ooty", coordinate: Fixtures.north(of: here, meters: 300_000))
        let result = DestinationSuggestions.suggestions(
            query: "", wishlist: [near], recent: [sameSpot, sameName, samePlace, fresh, fresh], from: here)
        #expect(result.map(\.destination) == [near, fresh])
        #expect(result.last?.source == .recent)
    }

    @Test func queryFiltersBothListsAndLimitsApply() {
        let wishlist = (1...8).map { RideDestination(name: "Lake \($0)", coordinate: Fixtures.north(of: here, meters: Double($0) * 1_000)) }
        let recent = (1...5).map { RideDestination(name: "Dhaba \($0)", coordinate: Fixtures.east(of: here, meters: Double($0) * 10_000)) }
        #expect(DestinationSuggestions.suggestions(query: "", wishlist: wishlist, recent: recent, from: here).count == 5 + 3)
        let lakes = DestinationSuggestions.suggestions(query: "lake", wishlist: wishlist, recent: recent, from: here)
        #expect(lakes.count == 5 && lakes.allSatisfy { $0.source == .wishlist })
        let dhabas = DestinationSuggestions.suggestions(query: " dhaba 2 ", wishlist: wishlist, recent: recent, from: here)
        #expect(dhabas.map(\.destination.name) == ["Dhaba 2"])
    }
}
