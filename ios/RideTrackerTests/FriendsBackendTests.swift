import Foundation
import RideKit
import Testing
@testable import RideTracker

@Suite("Friends on Supabase")
struct FriendsBackendTests {
    private func keys(_ row: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        return Set(try #require(object).keys)
    }

    @Test(arguments: ["rajan", "rahul_rides", "a.b.c", "abc", "x1234567890123456789"])
    func acceptsHandles(_ handle: String) {
        #expect(AccountService.isValidHandle(handle))
    }

    @Test(arguments: ["ab", "Rajan", "has space", "émile", "toolongtoolongtoolong", "dash-ed", ""])
    func rejectsHandles(_ handle: String) {
        #expect(!AccountService.isValidHandle(handle))
    }

    @Test func handlesAreTypedLooselyAndStoredCleanly() {
        #expect(AccountService.normalisedHandle("  @Rajan_Rides ") == "rajan_rides")
    }

    @MainActor @Test func cancelledLoadsAreNotShownAsErrors() {
        #expect(FriendsService.isCancellation(CancellationError()))
        #expect(FriendsService.isCancellation(URLError(.cancelled)))
        #expect(!FriendsService.isCancellation(URLError(.notConnectedToInternet)))
    }

    @Test func publishedRideMatchesTheSharedRidesTable() throws {
        let ride = SharedRide(id: UUID(), name: "Vainaad", startedAt: .now, endedAt: .now, distanceMeters: 34_800,
                              avgMovingSpeedMps: 12, stops: [], songs: [], photos: [])
        let row = SharedRideRow(ride, ownerID: UUID(), trackPath: "u/r/track")
        #expect(try keys(row) == ["ride_id", "owner_id", "name", "started_at", "ended_at", "distance_meters", "moving_seconds",
                                  "max_speed_mps", "avg_moving_speed_mps", "elevation_gain_meters", "track_path", "stops", "songs"])
    }

    @Test func publishedRideReadsBackTheSame() {
        let photoID = UUID()
        let stop = SharedRide.Stop(id: "s1", name: "Arafa Restaurant", category: "food",
                                   coordinate: Coordinate(latitude: 11.56, longitude: 76.37), arrivedAt: .now, photoIDs: [photoID.uuidString])
        let photo = SharedRide.Photo(id: photoID.uuidString, capturedAt: .now,
                                     coordinate: Coordinate(latitude: 11.56, longitude: 76.37), isVideo: true)
        let ride = SharedRide(id: UUID(), name: "Vainaad", startedAt: .now, endedAt: .now, stops: [stop], photos: [photo])
        let owner = UUID()
        let media = SharedMediaRow(photo, rideID: ride.id, ownerID: owner, path: "p", stopID: "s1")
        let back = SharedRideRow(ride, ownerID: owner, trackPath: "t").sharedRide(photos: [media])
        #expect(back.id == ride.id)
        #expect(back.stops == ride.stops)
        #expect(back.photos.first?.id == photoID.uuidString)
        #expect(back.photos.first?.isVideo == true)
        #expect(back.photos.first?.coordinate == photo.coordinate)
    }

    @Test func liveRowLetsTheServerOwnIdentityAndTime() throws {
        let live = LiveRide(rideID: UUID(), rideName: "Ride to Zostel Ooty", startedAt: .now, updatedAt: .now,
                            position: Coordinate(latitude: 11.41, longitude: 76.69), distanceMeters: 12_000,
                            isPaused: false, path: [Coordinate(latitude: 11.4, longitude: 76.6)])
        let keys = try keys(LiveRow(live))
        #expect(!keys.contains("owner_id") && !keys.contains("updated_at"))
        #expect(keys == ["ride_id", "ride_name", "started_at", "distance_meters", "is_paused", "latitude", "longitude", "path"])
        #expect(LiveRow(live).liveRide.position == live.position)
    }
}
