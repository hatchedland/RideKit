import Foundation
import SwiftData

/// The CloudKit schema can't change destructively once it's deployed to production, so the models
/// are versioned from day one. Future versions add a `RideTrackerSchemaV2` and a migration stage.
enum RideTrackerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Spot.self, Ride.self, MediaLink.self] }
}

enum RideTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RideTrackerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum Persistence {
    /// Syncs through the user's private iCloud database. Falls back to local-only storage when the
    /// device isn't signed in to iCloud. SwiftData then syncs once it is.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: RideTrackerSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .automatic
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
