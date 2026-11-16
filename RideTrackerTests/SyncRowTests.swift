import Foundation
import RideKit
import SwiftData
import Testing
@testable import RideTracker

/// The rows `SyncService` sends must match the columns in supabase/migrations, never send the
/// server's own fields, and change fingerprint exactly when their content changes.
@MainActor
@Suite("Sync rows")
struct SyncRowTests {
    let user = UUID()

    private func keys(_ row: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        return Set(try #require(object).keys)
    }

    private func context() throws -> ModelContext {
        let schema = Schema(versionedSchema: RideTrackerSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @Test func rideRowMatchesTheRidesTable() throws {
        let ride = Ride(id: UUID(), name: "Zostel ooty Diwali", startedAt: Date(timeIntervalSince1970: 1_000))
        ride.endedAt = Date(timeIntervalSince1970: 5_000)
        ride.trackData = Data([1, 2, 3])
        ride.destination = RideDestination(name: "Zostel Ooty", coordinate: Coordinate(latitude: 11.41, longitude: 76.69))
        let row = RideSyncRow(ride, userID: user)
        #expect(try keys(row) == ["id", "user_id", "name", "notes", "started_at", "ended_at", "distance_meters", "moving_seconds",
                                  "max_speed_mps", "avg_moving_speed_mps", "elevation_gain_meters", "track_path",
                                  "include_screenshots", "destination_name", "destination_latitude", "destination_longitude",
                                  "destination_spot_id", "destination_reached_at", "shared_with_friends", "shared_at"])
        #expect(row.trackPath == "\(user.uuidString.lowercased())/\(ride.id.uuidString.lowercased()).track")
    }

    @Test func rideWithoutTrackHasNoTrackPath() {
        let ride = Ride(id: UUID(), name: "Marathon", startedAt: .now)
        #expect(RideSyncRow(ride, userID: user).trackPath == nil)
    }

    @Test func fingerprintChangesOnlyWithContent() {
        let ride = Ride(id: UUID(), name: "Vainaad", startedAt: Date(timeIntervalSince1970: 1_000))
        let before = RideSyncRow(ride, userID: user).fingerprint
        #expect(RideSyncRow(ride, userID: user).fingerprint == before)
        ride.notes = "Mist all the way up the ghat"
        #expect(RideSyncRow(ride, userID: user).fingerprint != before)
    }

    @Test func otherRowsMatchTheirTablesAndNeverSendServerFields() throws {
        let context = try context()
        let ride = Ride(id: UUID(), name: "Vainaad", startedAt: .now)
        let spot = Spot(name: "Arafa Restaurant", coordinate: Coordinate(latitude: 11.56, longitude: 76.37), status: .visited, category: .food)
        spot.visits = [Date(timeIntervalSince1970: 2_000)]
        spot.ride = ride
        let link = MediaLink(candidate: MediaCandidate(id: "ASSET-1", capturedAt: .now, coordinate: nil, kind: .video), cloudIdentifier: "CLOUD-1")
        link.ride = ride
        link.spot = spot
        let song = PlayedSong(play: SongPlay(song: NowPlayingSong(id: "1", title: "Safarnama", artist: "Lucky Ali"), startedAt: .now, listenedSeconds: 200), at: nil)
        song.ride = ride
        context.insert(ride)
        context.insert(spot)
        context.insert(link)
        context.insert(song)

        let spotKeys = try keys(SpotSyncRow(spot))
        #expect(spotKeys.isSuperset(of: ["id", "ride_id", "name", "category", "status", "latitude", "longitude", "visits", "google_maps_url"]))
        let mediaKeys = try keys(MediaSyncRow(link))
        #expect(mediaKeys == ["id", "ride_id", "spot_id", "local_identifier", "cloud_identifier", "kind", "captured_at",
                              "latitude", "longitude", "is_manual", "shared_with_friends"])
        let songKeys = try keys(SongSyncRow(song))
        #expect(songKeys == ["id", "ride_id", "title", "artist", "album", "store_id", "started_at", "listened_seconds", "latitude", "longitude"])
        // The server owns updated_at and deleted_at; only rides carry user_id (others default to auth.uid()).
        for set in [spotKeys, mediaKeys, songKeys, try keys(RideSyncRow(ride, userID: user))] {
            #expect(!set.contains("updated_at") && !set.contains("deleted_at"))
        }
        #expect(!spotKeys.contains("user_id") && !mediaKeys.contains("user_id") && !songKeys.contains("user_id"))
        #expect(SpotSyncRow(spot).rideID == ride.id)
        #expect(MediaSyncRow(link).spotID == spot.id)
        #expect(MediaSyncRow(link).kind == "video")
    }

    @Test func pulledRowsWriteBackIntoModels() throws {
        let context = try context()
        let ride = Ride(id: UUID(), name: "Original", startedAt: .now)
        context.insert(ride)
        var row = RideSyncRow(ride, userID: user)
        row.name = "Renamed on another phone"
        row.notes = "Synced"
        row.write(to: ride)
        #expect(ride.name == "Renamed on another phone")
        #expect(ride.notes == "Synced")

        let spot = Spot(coordinate: Coordinate(latitude: 12, longitude: 77), status: .visited)
        context.insert(spot)
        var spotRow = SpotSyncRow(spot)
        spotRow.name = "Mari Amma Temple"
        spotRow.category = "monument"
        spotRow.rideID = ride.id
        spotRow.write(to: spot, rides: { $0 == ride.id ? ride : nil })
        #expect(spot.name == "Mari Amma Temple")
        #expect(spot.category == .monument)
        #expect(spot.ride?.id == ride.id)
    }

    @Test func mediaKeepsThisPhonesPhotosID() throws {
        let context = try context()
        let link = MediaLink(candidate: MediaCandidate(id: "THIS-PHONE", capturedAt: .now), cloudIdentifier: "CLOUD")
        context.insert(link)
        var row = MediaSyncRow(link)
        row.localIdentifier = "OTHER-PHONE"
        row.write(to: link, rides: { _ in nil }, spots: { _ in nil })
        #expect(link.localIdentifier == "THIS-PHONE")
    }
}

@MainActor
@Suite("Signing out")
struct SignOutTests {
    @Test func erasingRemovesTheRidersDataFromThePhone() throws {
        let schema = Schema(versionedSchema: RideTrackerSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let ride = Ride(id: UUID(), name: "Vainaad", startedAt: .now)
        context.insert(ride)
        let spot = Spot(name: "Arafa", coordinate: Coordinate(latitude: 11.5, longitude: 76.3), status: .visited)
        context.insert(spot)
        let link = MediaLink(candidate: MediaCandidate(id: "A", capturedAt: .now), cloudIdentifier: nil)
        link.ride = ride
        context.insert(link)
        try context.save()

        let sync = SyncService(context: context, account: AccountService())
        sync.eraseLocalData()

        #expect(try context.fetchCount(FetchDescriptor<Ride>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Spot>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MediaLink>()) == 0)
        #expect(sync.unsyncedCount == 0)
        #expect(sync.status == .idle)
    }
}
