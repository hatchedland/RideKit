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
        let schema = Schema(versionedSchema: RideTrackerSchemaCurrent.self)
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
        #expect(!ride.sharedWithFriends)
    }

    /// v1.1.0 stores (with songs) must keep everything and start out private when friends arrive.
    @Test func v2StoreOpensWithCurrentSchema() throws {
        let folder = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "rides.store")
        let rideID = UUID()

        do {
            let schema = Schema(versionedSchema: RideTrackerSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let ride = RideTrackerSchemaV2.Ride()
            ride.id = rideID
            ride.name = "Murthal run"
            let link = RideTrackerSchemaV2.MediaLink()
            link.localIdentifier = "ASSET-1"
            link.ride = ride
            let song = RideTrackerSchemaV2.PlayedSong()
            song.title = "Safarnama"
            song.ride = ride
            context.insert(ride)
            context.insert(link)
            context.insert(song)
            try context.save()
        }

        let schema = Schema(versionedSchema: RideTrackerSchemaCurrent.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: RideTrackerMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let ride = try #require(try context.fetch(FetchDescriptor<Ride>()).first)
        #expect(ride.id == rideID)
        #expect(ride.soundtrack.map(\.title) == ["Safarnama"])
        #expect(!ride.sharedWithFriends)
        #expect(ride.sharedAt == nil)
        let link = try #require(ride.media?.first)
        #expect(link.localIdentifier == "ASSET-1")
        #expect(!link.sharedWithFriends)

        ride.sharedWithFriends = true
        link.sharedWithFriends = true
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Ride>()).first?.sharedWithFriends == true)
    }

    /// Friends-era stores (what Personal builds on riders' phones hold) keep everything and start
    /// without a destination; one can be set afterwards.
    @Test func v3StoreOpensWithCurrentSchema() throws {
        let folder = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "rides.store")
        let rideID = UUID()

        do {
            let schema = Schema(versionedSchema: RideTrackerSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let ride = RideTrackerSchemaV3.Ride()
            ride.id = rideID
            ride.name = "Zostel ooty Diwali"
            ride.distanceMeters = 131_000
            ride.sharedWithFriends = true
            let spot = RideTrackerSchemaV3.Spot()
            spot.name = "Arafa Restaurant"
            spot.statusRaw = "wantToGo"
            let link = RideTrackerSchemaV3.MediaLink()
            link.localIdentifier = "ASSET-1"
            link.sharedWithFriends = true
            link.ride = ride
            let song = RideTrackerSchemaV3.PlayedSong()
            song.title = "Safarnama"
            song.ride = ride
            context.insert(ride)
            context.insert(spot)
            context.insert(link)
            context.insert(song)
            try context.save()
        }

        let schema = Schema(versionedSchema: RideTrackerSchemaCurrent.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: RideTrackerMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let ride = try #require(try context.fetch(FetchDescriptor<Ride>()).first)
        #expect(ride.id == rideID)
        #expect(ride.name == "Zostel ooty Diwali")
        #expect(ride.distanceMeters == 131_000)
        #expect(ride.sharedWithFriends)
        #expect(ride.media?.first?.sharedWithFriends == true)
        #expect(ride.soundtrack.map(\.title) == ["Safarnama"])
        #expect(ride.destination == nil)
        #expect(ride.destinationReachedAt == nil)
        let spot = try #require(try context.fetch(FetchDescriptor<Spot>()).first)
        #expect(spot.status == .wantToGo)

        let destination = RideDestination(name: "Zostel Ooty", coordinate: Coordinate(latitude: 11.41, longitude: 76.69), spotID: spot.id)
        ride.destination = destination
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Ride>()).first?.destination == destination)
        ride.destination = nil
        #expect(ride.destinationName == nil && ride.destinationSpotID == nil)
    }
}
