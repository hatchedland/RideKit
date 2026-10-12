import Foundation
import SwiftData

// The CloudKit schema can't change destructively once it's deployed to production, so the models
// are versioned. Each released version is **frozen** below as nested copies of its models, so
// SwiftData can recognise stores written by that version. The top-level models are always the
// latest version. To change the schema: freeze the current models as a new `RideTrackerSchemaVn`,
// change the top-level models (additive only), and add a migration stage.

/// v1.0.0: spots, rides, media links.
enum RideTrackerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Spot.self, Ride.self, MediaLink.self] }

    @Model final class Spot {
        var id: UUID = UUID()
        var name: String = ""
        var nameIsSuggested: Bool = false
        var notes: String = ""
        var categoryRaw: String = "other"
        var statusRaw: String = "visited"
        var rating: Int?
        var priority: Int?
        var bestSeason: String?
        var latitude: Double = 0
        var longitude: Double = 0
        var altitude: Double?
        var address: String?
        var locality: String?
        var googleMapsURL: String = ""
        var sourceURL: String?
        var createdAt: Date = Date.now
        var visits: [Date] = []
        var autoVisitedByRideID: UUID?
        var ride: Ride?
        @Relationship(deleteRule: .cascade, inverse: \MediaLink.spot) var media: [MediaLink]? = []
        init() {}
    }

    @Model final class Ride {
        var id: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var startedAt: Date = Date.now
        var endedAt: Date = Date.now
        var distanceMeters: Double = 0
        var movingSeconds: Double = 0
        var maxSpeedMps: Double = 0
        var avgMovingSpeedMps: Double = 0
        var elevationGainMeters: Double = 0
        @Attribute(.externalStorage) var trackData: Data?
        var albumLocalIdentifier: String?
        var albumSweepUntil: Date?
        var includeScreenshots: Bool = false
        @Relationship(deleteRule: .nullify, inverse: \Spot.ride) var spots: [Spot]? = []
        @Relationship(deleteRule: .cascade, inverse: \MediaLink.ride) var media: [MediaLink]? = []
        init() {}
    }

    @Model final class MediaLink {
        var id: UUID = UUID()
        var localIdentifier: String = ""
        var cloudIdentifier: String?
        var kindRaw: String = "photo"
        var capturedAt: Date = Date.now
        var latitude: Double?
        var longitude: Double?
        var isManual: Bool = false
        var spot: Spot?
        var ride: Ride?
        init() {}
    }
}

/// v1.1.0: adds `PlayedSong` (the ride's Apple Music soundtrack) and `Ride.songs`.
enum RideTrackerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 1, 0)
    static var models: [any PersistentModel.Type] { [Spot.self, Ride.self, MediaLink.self, PlayedSong.self] }
}

enum RideTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RideTrackerSchemaV1.self, RideTrackerSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: RideTrackerSchemaV1.self, toVersion: RideTrackerSchemaV2.self)]
    }
}

enum Persistence {
    /// Syncs through the user's private iCloud database. Falls back to local-only storage when the
    /// device isn't signed in to iCloud. SwiftData then syncs once it is.
    /// The Personal build (free Apple ID, no iCloud entitlement) is always local-only.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: RideTrackerSchemaV2.self)
        #if PERSONAL_TEAM
        let cloudKit: ModelConfiguration.CloudKitDatabase = .none
        #else
        let cloudKit: ModelConfiguration.CloudKitDatabase = inMemory ? .none : .automatic
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: RideTrackerMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            fatalError("Could not open the ride database: \(error)")
        }
    }
}
