import Foundation
import RideKit
import SwiftData
import Testing
@testable import RideTracker

/// What friends get from a ride: only chosen photos, spots as named stops, the soundtrack, and
/// nothing near home.
@MainActor
@Suite("Friends: sharing a ride")
struct FriendsTests {
    let home = Coordinate(latitude: 28.729, longitude: 77.152)
    let dhaba = Coordinate(latitude: 29.0418, longitude: 77.0697)
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeRide(in context: ModelContext) -> Ride {
        let ride = Ride(id: UUID(), name: "Murthal run", startedAt: start)
        ride.endedAt = start.addingTimeInterval(3600)
        ride.distanceMeters = 36_000
        context.insert(ride)

        let points = (0...60).map { minute in
            TrackPoint(timestamp: start.addingTimeInterval(Double(minute) * 60),
                       coordinate: home.interpolated(to: dhaba, fraction: Double(minute) / 60), speed: 10)
        }
        ride.trackData = try? TrackCodec.encode(points)

        let spot = Spot(name: "Amrik Sukhdev", coordinate: dhaba.interpolated(to: home, fraction: 0.1), status: .visited, category: .food)
        spot.visits = [start.addingTimeInterval(54 * 60)]
        spot.ride = ride
        context.insert(spot)

        func photo(_ id: String, minute: Double, at coordinate: Coordinate?, shared: Bool, spot: Spot? = nil) {
            let link = MediaLink(candidate: MediaCandidate(id: id, capturedAt: start.addingTimeInterval(minute * 60),
                                                           coordinate: coordinate, kind: .photo), cloudIdentifier: nil)
            link.sharedWithFriends = shared
            link.ride = ride
            link.spot = spot
            context.insert(link)
        }
        photo("at-gate", minute: 0, at: home, shared: true)
        photo("at-dhaba", minute: 55, at: spot.coordinate, shared: true, spot: spot)
        photo("private", minute: 30, at: home.interpolated(to: dhaba, fraction: 0.5), shared: false)

        let song = PlayedSong(play: SongPlay(song: NowPlayingSong(id: "1", title: "Safarnama", artist: "Lucky Ali", storeID: "1"),
                                             startedAt: start.addingTimeInterval(600), listenedSeconds: 200), at: home)
        song.ride = ride
        context.insert(song)
        return ride
    }

    @Test func sharesOnlyChosenPhotosAndHidesHome() throws {
        let container = Persistence.makeContainer(inMemory: true)
        let ride = makeRide(in: container.mainContext)
        let track = ride.decodedTrack()

        let shared = FriendsService.sharedRide(from: ride, track: track).redacted(by: SharePrivacy(), track: track)

        #expect(shared.id == ride.id)
        #expect(shared.name == "Murthal run")
        #expect(shared.distanceMeters == 36_000)
        #expect(!shared.photos.contains { $0.id == "private" })  // not chosen
        #expect(!shared.photos.contains { $0.id == "at-gate" })  // at the start: hidden with its stop
        #expect(shared.photos.map(\.id) == ["at-dhaba"])
        let stop = try #require(shared.stops.first { $0.name == "Amrik Sukhdev" })
        #expect(stop.category == "food")
        #expect(stop.photoIDs == ["at-dhaba"])
        #expect(shared.songs.map(\.title) == ["Safarnama"])
    }

    @Test func privacyZoneRemovesStopsInside() {
        let container = Persistence.makeContainer(inMemory: true)
        let ride = makeRide(in: container.mainContext)
        let track = ride.decodedTrack()
        let zone = PrivacyZone(name: "Dhaba", center: dhaba, radius: 5_000)

        let shared = FriendsService.sharedRide(from: ride, track: track)
            .redacted(by: SharePrivacy(zones: [zone], endTrim: 0), track: track)

        #expect(!shared.stops.contains { $0.name == "Amrik Sukhdev" })
        #expect(shared.photos.map(\.id) == ["at-gate"]) // end trim is off, and home has no zone here
    }
}
