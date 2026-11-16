import Foundation
import RideKit
import Testing
@testable import RideTracker

@Suite("Friends on Supabase")
struct FriendsBackendTests {
    let code = "3f2a9c1e7b5d4e60a8c2f1d0b9e7a6c5"

    private func keys(_ row: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        return Set(try #require(object).keys)
    }

    @Test func findsTheCodeInALinkOrAPastedMessage() {
        #expect(InviteCode.find(in: "ridetracker://invite/\(code)") == code)
        let whatsapp = """
        Rajan wants to ride with you on Ride Tracker 🏍️
        Tap to see my rides: ridetracker://invite/\(code)
        Or open Ride Tracker › Friends › Paste invite. Code: \(code.uppercased())
        """
        #expect(InviteCode.find(in: whatsapp) == code)
        #expect(InviteCode.find(in: "no code here, just a ride to Ooty") == nil)
        #expect(InviteCode.find(in: "3f2a9c1e7b5d4e60") == nil) // too short
        #expect(InviteCode.link(code).absoluteString == "ridetracker://invite/\(code)")
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
