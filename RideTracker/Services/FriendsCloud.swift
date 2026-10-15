import CloudKit
import Foundation
import RideKit

/// The CloudKit side of friends, with no backend of our own.
///
/// Each rider has one record zone, **Friends**, in their *private* database, and shares the whole
/// zone (`CKShare(recordZoneID:)`) with the friends they invite. The zone holds:
/// - `SharedRide` records (one per shared ride): `payload` = `SharedRide` JSON, `track` = redacted
///   `TrackCodec` blob, `photos` = JPEG copies of the photos the rider chose, in `payload.photos` order.
/// - one `LiveRide` record (`live`) while sharing a ride live: `payload` = `LiveRide` JSON.
///
/// A friend sees each accepted share as a zone in their *shared* database. Sharing is one-way:
/// Aman seeing my rides doesn't let me see his until he invites me back.
enum FriendsCloud {
    static let containerID = "iCloud.com.hatchedland.ridetracker"
    static let zoneID = CKRecordZone.ID(zoneName: "Friends", ownerName: CKCurrentUserDefaultName)
    static let liveRecordName = "live"

    enum RecordType {
        static let sharedRide = "SharedRide"
        static let liveRide = "LiveRide"
    }

    enum Field {
        static let payload = "payload"
        static let track = "track"
        static let photos = "photos"
        static let endedAt = "endedAt"
    }

    static var container: CKContainer { CKContainer(identifier: containerID) }

    // MARK: Owner side

    /// Creates the Friends zone if it doesn't exist yet. Cheap to call repeatedly.
    static func ensureZone() async throws {
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    }

    /// The zone-wide share friends join through, created on first use.
    static func share(title: String) async throws -> CKShare {
        try await ensureZone()
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none
        let saved = try await database.modifyRecords(saving: [share], deleting: [])
        guard case .success(let record) = saved.saveResults[shareID], let created = record as? CKShare else {
            throw CKError(.internalError)
        }
        return created
    }

    /// Publishes or replaces a shared ride. `photoFiles` are in `ride.photos` order.
    static func publish(_ ride: SharedRide, track: [TrackPoint], photoFiles: [URL]) async throws {
        try await ensureZone()
        let folder = URL.temporaryDirectory.appending(path: "share-\(ride.id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let record = CKRecord(recordType: RecordType.sharedRide, recordID: rideRecordID(ride.id))
        record[Field.payload] = try ride.encoded() as NSData
        record[Field.endedAt] = ride.endedAt as NSDate
        if !track.isEmpty {
            let trackFile = folder.appending(path: "track.rtk")
            try TrackCodec.encode(track).write(to: trackFile)
            record[Field.track] = CKAsset(fileURL: trackFile)
        }
        record[Field.photos] = photoFiles.isEmpty ? nil : photoFiles.map { CKAsset(fileURL: $0) } as NSArray
        try await save(record)
    }

    static func unpublish(rideID: UUID) async throws {
        try await delete(rideRecordID(rideID))
    }

    static func publishLive(_ live: LiveRide) async throws {
        let record = CKRecord(recordType: RecordType.liveRide, recordID: CKRecord.ID(recordName: liveRecordName, zoneID: zoneID))
        record[Field.payload] = try live.encoded() as NSData
        try await save(record)
    }

    static func endLive() async throws {
        try await delete(CKRecord.ID(recordName: liveRecordName, zoneID: zoneID))
    }

    // MARK: Friend side

    /// Accepts an invitation the rider opened.
    static func accept(_ metadata: CKShare.Metadata) async throws -> String {
        let share = try await container.accept(metadata)
        return displayName(of: share)
    }

    /// Everything friends share with this rider, one entry per friend.
    static func fetchFriends() async throws -> [FriendSnapshot] {
        let database = container.sharedCloudDatabase
        let zones = try await database.allRecordZones()
        var friends: [FriendSnapshot] = []
        for zone in zones {
            do {
                friends.append(try await fetchFriend(zoneID: zone.zoneID, in: database))
            } catch {
                // One friend's zone failing (e.g. they stopped sharing mid-fetch) shouldn't hide the others.
                continue
            }
        }
        return friends.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Stops seeing a friend's rides (removes their zone from this rider's shared database).
    static func leave(zoneID: CKRecordZone.ID) async throws {
        _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
    }

    // MARK: Helpers

    private static func fetchFriend(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> FriendSnapshot {
        var rides: [FriendSnapshot.Ride] = []
        var live: LiveRide?
        var name = zoneID.ownerName
        var token: CKServerChangeToken?
        var moreComing = true
        let cache = cacheFolder(for: zoneID)

        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                guard case .success(let modification) = result else { continue }
                let record = modification.record
                switch record.recordType {
                case RecordType.sharedRide:
                    if let ride = parseRide(record, cache: cache) { rides.append(ride) }
                case RecordType.liveRide:
                    if let data = record[Field.payload] as? Data { live = try? LiveRide.decode(data) }
                case "cloudkit.share":
                    if let share = record as? CKShare { name = displayName(of: share) }
                default:
                    break
                }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        rides.sort { $0.ride.endedAt > $1.ride.endedAt }
        return FriendSnapshot(zoneID: zoneID, name: name, rides: rides, live: live)
    }

    private static func parseRide(_ record: CKRecord, cache: URL) -> FriendSnapshot.Ride? {
        guard let data = record[Field.payload] as? Data, let ride = try? SharedRide.decode(data) else { return nil }
        var track: [TrackPoint] = []
        if let asset = record[Field.track] as? CKAsset, let url = asset.fileURL, let blob = try? Data(contentsOf: url) {
            track = (try? TrackCodec.decode(blob)) ?? []
        }
        // CloudKit's asset files are temporary; keep a copy so photos still show offline.
        var photoFiles: [String: URL] = [:]
        let assets = (record[Field.photos] as? [CKAsset]) ?? []
        for (photo, asset) in zip(ride.photos, assets) {
            guard let source = asset.fileURL else { continue }
            let target = cache.appending(path: "\(ride.id.uuidString)-\(photo.id.replacing("/", with: "_")).jpg")
            if !FileManager.default.fileExists(atPath: target.path()) {
                try? FileManager.default.copyItem(at: source, to: target)
            }
            photoFiles[photo.id] = target
        }
        return FriendSnapshot.Ride(ride: ride, track: track, photoFiles: photoFiles)
    }

    private static func cacheFolder(for zoneID: CKRecordZone.ID) -> URL {
        let safe = zoneID.ownerName.replacing(/[^\w-]/, with: "_")
        let url = URL.cachesDirectory.appending(path: "Friends/\(safe)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func displayName(of share: CKShare) -> String {
        if let components = share.owner.userIdentity.nameComponents {
            let name = components.formatted(.name(style: .short))
            if !name.isEmpty { return name }
        }
        if let title = share[CKShare.SystemFieldKey.title] as? String, !title.isEmpty {
            return title.replacing("’s rides", with: "")
        }
        return "Friend"
    }

    private static func rideRecordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "ride-\(id.uuidString)", zoneID: zoneID)
    }

    private static func save(_ record: CKRecord) async throws {
        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys, atomically: true
        )
        if case .failure(let error) = result.saveResults[record.recordID] { throw error }
    }

    private static func delete(_ id: CKRecord.ID) async throws {
        do {
            let result = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [id])
            if case .failure(let error) = result.deleteResults[id], (error as? CKError)?.code != .unknownItem { throw error }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // Nothing to delete.
        }
    }
}

/// What one friend shares, fetched from their zone.
struct FriendSnapshot: Identifiable, Sendable {
    var zoneID: CKRecordZone.ID
    var name: String
    var rides: [Ride]
    var live: LiveRide?

    var id: String { zoneID.ownerName }

    struct Ride: Identifiable, Sendable {
        var ride: SharedRide
        var track: [TrackPoint]
        /// `SharedRide.Photo.id` → cached JPEG.
        var photoFiles: [String: URL]

        var id: UUID { ride.id }
    }
}
