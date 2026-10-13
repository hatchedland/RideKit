import Foundation
import Testing
@testable import RideKit

@Suite("Photo trail")
struct TrailTests {
    let start = Fixtures.start
    /// 60 minutes heading north at 10 m/s: 36 km, one fix per second.
    let track = Fixtures.track(segments: [(3600, 10)])

    func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
    func position(_ minutes: Double) -> Coordinate { Fixtures.north(of: Fixtures.indiaGate, meters: minutes * 600) }

    func build(media: [Trail.Media] = [], spots: [Trail.Spot] = [], songs: [(id: String, startedAt: Date)] = []) -> Trail {
        Trail.build(rideStart: start, rideEnd: at(60), track: track, media: media, spots: spots, songs: songs)
    }

    @Test func noMediaNoSpotsIsOneLegOfTheWholeRide() {
        let trail = build()
        #expect(trail.stops.isEmpty)
        #expect(trail.legs.count == 1)
        #expect(trail.legs[0].start == start)
        #expect(trail.legs[0].end == at(60))
        #expect(abs((trail.legs[0].distance ?? 0) - 36_000) < 1)
    }

    @Test func photosAtASpotFormThatSpotsStop() {
        let spotID = UUID()
        let trail = build(
            media: [
                Trail.Media(id: "b", capturedAt: at(21), coordinate: position(20), spotID: spotID),
                Trail.Media(id: "a", capturedAt: at(20), coordinate: position(20), spotID: spotID),
            ],
            spots: [Trail.Spot(id: spotID, coordinate: position(20), markedAt: at(20.5))]
        )
        #expect(trail.stops.count == 1)
        let stop = trail.stops[0]
        #expect(stop.kind == .spot(spotID))
        #expect(stop.id == spotID.uuidString)
        #expect(stop.mediaIDs == ["a", "b"])
        #expect(stop.arrivedAt == at(20))
        #expect(stop.departedAt == at(21))
        #expect(abs((stop.distanceFromStart ?? 0) - 12_000) < 1)
    }

    @Test func spotMarkedWithoutPhotosStillAppears() {
        let spotID = UUID()
        let trail = build(spots: [Trail.Spot(id: spotID, coordinate: position(30), markedAt: at(30))])
        #expect(trail.stops.map(\.kind) == [.spot(spotID)])
        #expect(trail.stops[0].mediaIDs.isEmpty)
        #expect(trail.legs.count == 2)
    }

    @Test func nearbyPhotosAwayFromSpotsCluster() {
        let base = position(10)
        let trail = build(media: [
            Trail.Media(id: "p1", capturedAt: at(10), coordinate: base),
            Trail.Media(id: "p2", capturedAt: at(12), coordinate: Fixtures.east(of: base, meters: 80)),
            Trail.Media(id: "p3", capturedAt: at(14), coordinate: Fixtures.east(of: base, meters: 140)),
        ])
        #expect(trail.stops.count == 1)
        #expect(trail.stops[0].kind == .cluster)
        #expect(trail.stops[0].id == "p1")
        #expect(trail.stops[0].mediaIDs == ["p1", "p2", "p3"])
    }

    @Test func farOrLatePhotosStartANewCluster() {
        let base = position(10)
        let trail = build(media: [
            Trail.Media(id: "p1", capturedAt: at(10), coordinate: base),
            Trail.Media(id: "far", capturedAt: at(11), coordinate: Fixtures.east(of: base, meters: 400)),
            Trail.Media(id: "late", capturedAt: at(30), coordinate: Fixtures.east(of: base, meters: 400)),
        ])
        #expect(trail.stops.map(\.mediaIDs) == [["p1"], ["far"], ["late"]])
    }

    @Test func clusterGapIsMeasuredFromTheLatestPhoto() {
        // A long stop: photos every 8 minutes for half an hour stay one stop.
        let base = position(5)
        let media = (0..<5).map { Trail.Media(id: "p\($0)", capturedAt: at(5 + Double($0) * 8), coordinate: base) }
        #expect(build(media: media).stops.count == 1)
    }

    @Test func photoWithoutLocationJoinsTheStopClosestInTime() {
        let spotID = UUID()
        let trail = build(
            media: [
                Trail.Media(id: "located", capturedAt: at(20), coordinate: position(20), spotID: spotID),
                Trail.Media(id: "noGPS", capturedAt: at(26)),
            ],
            spots: [Trail.Spot(id: spotID, coordinate: position(20), markedAt: at(20))]
        )
        #expect(trail.stops[0].mediaIDs == ["located", "noGPS"])
        #expect(trail.legs.allSatisfy { $0.mediaIDs.isEmpty })
    }

    @Test func photoWithoutLocationFarFromStopsIsOnTheRoad() {
        let trail = build(media: [
            Trail.Media(id: "stop", capturedAt: at(20), coordinate: position(20)),
            Trail.Media(id: "early", capturedAt: at(2)),
            Trail.Media(id: "late", capturedAt: at(50)),
        ])
        #expect(trail.stops.map(\.mediaIDs) == [["stop"]])
        #expect(trail.legs.map(\.mediaIDs) == [["early"], ["late"]])
    }

    @Test func legsJoinStopsInOrderWithDistances() {
        let trail = build(media: [
            Trail.Media(id: "second", capturedAt: at(40), coordinate: position(40)),
            Trail.Media(id: "first", capturedAt: at(10), coordinate: position(10)),
        ])
        #expect(trail.stops.map(\.id) == ["first", "second"])
        #expect(trail.legs.count == 3)
        let distances = trail.legs.map { ($0.distance ?? 0) / 1000 }
        #expect(abs(distances[0] - 6) < 0.01)
        #expect(abs(distances[1] - 18) < 0.01)
        #expect(abs(distances[2] - 12) < 0.01)
        #expect(trail.legs[1].start == at(10))
        #expect(trail.legs[1].end == at(40))
    }

    @Test func songsLandOnTheLegTheyStartedOn() {
        let trail = build(
            media: [Trail.Media(id: "stop", capturedAt: at(30), coordinate: position(30))],
            songs: [("s2", at(45)), ("s1", at(5)), ("atStop", at(30))]
        )
        #expect(trail.legs[0].songIDs == ["s1"])
        #expect(trail.legs[1].songIDs == ["atStop", "s2"])
    }

    @Test func withoutTrackDistancesAreNil() {
        let trail = Trail.build(rideStart: start, rideEnd: at(60), track: [],
                                media: [Trail.Media(id: "p", capturedAt: at(10), coordinate: position(10))], spots: [])
        #expect(trail.stops.count == 1)
        #expect(trail.stops[0].distanceFromStart == nil)
        #expect(trail.legs.allSatisfy { $0.distance == nil })
    }

    @Test func spotNotPassedInIsPlacedAtItsPhoto() {
        let spotID = UUID()
        let trail = build(media: [Trail.Media(id: "p", capturedAt: at(10), coordinate: position(10), spotID: spotID)])
        #expect(trail.stops.first?.kind == .spot(spotID))
        #expect(trail.stops.first?.coordinate == position(10))
    }

    @Test func odometerInterpolatesAndClamps() {
        let odometer = Odometer(track: track)
        #expect(odometer.distance(at: at(-5)) == 0)
        #expect(abs((odometer.distance(at: start.addingTimeInterval(10.5)) ?? 0) - 105) < 0.01)
        #expect(abs((odometer.distance(at: at(90)) ?? 0) - 36_000) < 1)
        #expect(Odometer(track: []).distance(at: start) == nil)
    }
}
