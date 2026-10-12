import Foundation
import RideKit
import SwiftData
import Testing
@testable import RideTracker

/// Stores already on riders' phones were written by v1. Opening them with the current schema must
/// keep every ride, spot and photo link.
@MainActor
@Suite("Schema migration")
struct MigrationTests {
    @Test func v1StoreOpensWithCurrentSchema() throws {
        let folder = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "rides.store")
        let rideID = UUID()

        // Write a store exactly as v1.0.0 did.
        do {
            let schema = Schema(versionedSchema: RideTrackerSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let ride = RideTrackerSchemaV1.Ride()
            ride.id = rideID
            ride.name = "Murthal run"
            ride.distanceMeters = 42_000
            let spot = RideTrackerSchemaV1.Spot()
            spot.name = "Amrik Sukhdev"
            spot.googleMapsURL = "https://www.google.com/maps/search/?api=1&query=29.041800,77.069700"
            spot.ride = ride
            let link = RideTrackerSchemaV1.MediaLink()
            link.localIdentifier = "ASSET-1"
            link.ride = ride
            link.spot = spot
            context.insert(ride)
            context.insert(spot)
            context.insert(link)
            try context.save()
        }

        // Open it with the current schema and migration plan, as the updated app does.
        let schema = Schema(versionedSchema: RideTrackerSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: RideTrackerMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let rides = try context.fetch(FetchDescriptor<Ride>())
        #expect(rides.count == 1)
        let ride = try #require(rides.first)
        #expect(ride.id == rideID)
        #expect(ride.name == "Murthal run")
        #expect(ride.distanceMeters == 42_000)
        #expect(ride.spots?.first?.name == "Amrik Sukhdev")
        #expect(ride.spots?.first?.googleMapsURL.hasSuffix("query=29.041800,77.069700") == true)
        #expect(ride.media?.first?.localIdentifier == "ASSET-1")
        #expect(ride.media?.first?.spot?.name == "Amrik Sukhdev")
        #expect(ride.songs?.isEmpty ?? true)

        // And the new data can be added.
        let play = SongPlay(song: NowPlayingSong(id: "1", title: "Safarnama", artist: "Lucky Ali"), startedAt: .now, listenedSeconds: 200)
        let song = PlayedSong(play: play, at: nil)
        song.ride = ride
        context.insert(song)
        try context.save()
        #expect(ride.soundtrack.map(\.title) == ["Safarnama"])
    }
}
